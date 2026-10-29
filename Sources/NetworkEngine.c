#include "NetworkEngine.h"
#include <curl/curl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#ifndef RP_VERSION
#define RP_VERSION "development"
#endif

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t join_lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_int stopped = 1;
static RPState state;
static pthread_t threads[33];
static int thread_count;
static pthread_once_t once = PTHREAD_ONCE_INIT;
typedef struct {
    char url[2048];
    double mbps;
    int kind;
    curl_off_t last;
    size_t remaining;
    unsigned char payload[65536];
} Worker;
static Worker workers[33];
static void init_curl(void) { curl_global_init(CURL_GLOBAL_DEFAULT); }
static void message(const char *msg, int error) {
    pthread_mutex_lock(&lock);
    snprintf(state.message, sizeof(state.message), "%s", msg);
    state.event_id++;
    state.errors += error;
    pthread_mutex_unlock(&lock);
}
static int pause_for(int tenths) {
    for(int i=0;i<tenths && !atomic_load(&stopped);i++) usleep(100000);
    return atomic_load(&stopped);
}
static size_t discard(char *p, size_t a, size_t b, void *v) {
    (void)p; (void)v;
    return atomic_load(&stopped) ? 0 : a*b;
}
static size_t receive(char *p, size_t a, size_t b, void *v) {
    (void)p; (void)v;
    if(atomic_load(&stopped)) return 0;
    pthread_mutex_lock(&lock);
    state.downloaded += a*b;
    pthread_mutex_unlock(&lock);
    return a*b;
}
static size_t supply(char *p, size_t a, size_t b, void *v) {
    Worker *w = v;
    if(atomic_load(&stopped)) return CURL_READFUNC_ABORT;
    size_t n = a*b;
    if(n>sizeof(w->payload)) n=sizeof(w->payload);
    if(n>w->remaining) n=w->remaining;
    memcpy(p,w->payload,n);
    w->remaining-=n;
    return n;
}
static int progress(void *v, curl_off_t dt, curl_off_t dn, curl_off_t ut, curl_off_t un) {
    (void)dt;(void)dn;(void)ut;
    Worker *w=v;
    if(w->kind==1 && un>w->last) {
        pthread_mutex_lock(&lock);
        state.uploaded += (uint64_t)(un-w->last);
        pthread_mutex_unlock(&lock);
        w->last=un;
    }
    return atomic_load(&stopped);
}
static void *run(void *v) {
    Worker *w=v;
    CURL *c=curl_easy_init();
    if(!c) { message("Could not create HTTP connection",1); return NULL; }
    curl_easy_setopt(c,CURLOPT_URL,w->url);
    curl_easy_setopt(c,CURLOPT_NOSIGNAL,1L);
    curl_easy_setopt(c,CURLOPT_CONNECTTIMEOUT,8L);
    curl_easy_setopt(c,CURLOPT_NOPROGRESS,0L);
    curl_easy_setopt(c,CURLOPT_XFERINFOFUNCTION,progress);
    curl_easy_setopt(c,CURLOPT_XFERINFODATA,w);
    curl_easy_setopt(c,CURLOPT_USERAGENT,"InternetPulse/" RP_VERSION " (bandwidth test)");
    curl_easy_setopt(c,CURLOPT_FAILONERROR,1L);
    curl_easy_setopt(c,CURLOPT_PROTOCOLS_STR,"http,https");
    curl_easy_setopt(c,CURLOPT_REDIR_PROTOCOLS_STR,"http,https");
    curl_easy_setopt(c,CURLOPT_FOLLOWLOCATION,1L);
    curl_easy_setopt(c,CURLOPT_MAXREDIRS,3L);
    curl_easy_setopt(c,CURLOPT_LOW_SPEED_LIMIT,1L);
    curl_easy_setopt(c,CURLOPT_LOW_SPEED_TIME,20L);
    struct curl_slist *headers=NULL;
    headers=curl_slist_append(headers,"Cache-Control: no-cache");
    headers=curl_slist_append(headers,"Accept-Encoding: identity");
    if(w->kind==0) {
        curl_easy_setopt(c,CURLOPT_WRITEFUNCTION,receive);
        curl_easy_setopt(c,CURLOPT_MAX_RECV_SPEED_LARGE,(curl_off_t)(w->mbps*125000));
        curl_easy_setopt(c,CURLOPT_BUFFERSIZE,w->mbps==0 ? 262144L : 16384L);
    } else if(w->kind==1) {
        arc4random_buf(w->payload,sizeof(w->payload));
        headers=curl_slist_append(headers,"Content-Type: application/octet-stream");
        curl_easy_setopt(c,CURLOPT_UPLOAD,1L);
        curl_easy_setopt(c,CURLOPT_READFUNCTION,supply);
        curl_easy_setopt(c,CURLOPT_READDATA,w);
        curl_easy_setopt(c,CURLOPT_WRITEFUNCTION,discard);
        curl_easy_setopt(c,CURLOPT_MAX_SEND_SPEED_LARGE,(curl_off_t)(w->mbps*125000));
        curl_easy_setopt(c,CURLOPT_UPLOAD_BUFFERSIZE,w->mbps==0 ? 262144L : 16384L);
    } else {
        curl_easy_setopt(c,CURLOPT_NOBODY,1L);
        curl_easy_setopt(c,CURLOPT_TIMEOUT,5L);
        curl_easy_setopt(c,CURLOPT_WRITEFUNCTION,discard);
    }
    curl_easy_setopt(c,CURLOPT_HTTPHEADER,headers);
    int failures=0;
    while(!atomic_load(&stopped)) {
        w->last=0;
        if(w->kind==1) {
            // Bounded requests: about 20 seconds of data, never stored on disk.
            double bytes=w->mbps==0 ? 33554432 : w->mbps*125000*20;
            if(bytes<262144) bytes=262144;
            if(bytes>33554432) bytes=33554432;
            w->remaining=(size_t)bytes;
            curl_easy_setopt(c,CURLOPT_INFILESIZE_LARGE,(curl_off_t)w->remaining);
        }
        CURLcode r=curl_easy_perform(c);
        long status=0;
        curl_easy_getinfo(c,CURLINFO_RESPONSE_CODE,&status);
        curl_off_t received=0;
        curl_easy_getinfo(c,CURLINFO_SIZE_DOWNLOAD_T,&received);
        if(w->kind==0 && r==CURLE_OK && received==0) r=CURLE_GOT_NOTHING;
        char *content_type=NULL;
        curl_easy_getinfo(c,CURLINFO_CONTENT_TYPE,&content_type);
        if(w->kind==0 && r==CURLE_OK && content_type && strstr(content_type,"text/html")) r=CURLE_WEIRD_SERVER_REPLY;
        if(atomic_load(&stopped)) break;
        if(r==CURLE_OK && status>=200 && status<300) {
            if(w->kind==2) {
                double time=0;
                curl_easy_getinfo(c,CURLINFO_STARTTRANSFER_TIME,&time);
                pthread_mutex_lock(&lock);
                state.latency_ms=time*1000;
                pthread_mutex_unlock(&lock);
                pause_for(20);
            } else {
                if(failures) message(w->kind==0 ? "Download restored" : "Upload restored",0);
                // Empty downloads are rejected above; successful transfers can restart immediately.
            }
            failures=0;
        } else {
            failures++;
            if(w->kind==2) {
                pthread_mutex_lock(&lock); state.latency_ms=-1; pthread_mutex_unlock(&lock);
                pause_for(30);
            } else {
                char msg[256];
                int delay=failures<5 ? (1<<failures) : 30;
                snprintf(msg,sizeof(msg),"%s: %s (HTTP %ld). Retry in %d s", w->kind==0 ? "Download" : "Upload",curl_easy_strerror(r),status,delay);
                message(msg,1);
                pause_for(delay*10);
            }
        }
    }
    curl_slist_free_all(headers);
    curl_easy_cleanup(c);
    return NULL;
}
int rp_start(const char *d, const char *u, double down, double up) {
    return rp_start_parallel(d,u,down,up,1,0);
}
int rp_start_parallel(const char *d, const char *u, double down, double up, int streams, int unlimited) {
    if(thread_count || !d || !u || !isfinite(down) || !isfinite(up) || (!down && !up) || streams<1 || streams>16 || down<0 || up<0) return 0;
    pthread_once(&once,init_curl);
    pthread_mutex_lock(&lock); memset(&state,0,sizeof(state)); state.latency_ms=-1; pthread_mutex_unlock(&lock);
    atomic_store(&stopped,0);
    for(int i=0;i<streams*2+1;i++) {
        int k=i==streams*2 ? 2 : (i<streams ? 0 : 1);
        if((k==0 && down<=0) || (k==1 && up<=0)) continue;
        Worker *w=&workers[i]; memset(w,0,sizeof(*w));
        w->kind=k; w->mbps=unlimited ? 0 : (k==0 ? down : up)/streams;
        snprintf(w->url,sizeof(w->url),"%s",k==1 ? u : (down>0 ? d : u));
        if(pthread_create(&threads[thread_count],NULL,run,w)) {
            message("Could not start network worker",1);
            atomic_store(&stopped,1); return 0;
        }
        thread_count++;
    }
    return 1;
}
void rp_request_stop(void) { atomic_store(&stopped,1); }
void rp_join(void) {
    pthread_mutex_lock(&join_lock);
    for(int i=0;i<thread_count;i++) pthread_join(threads[i],NULL);
    thread_count=0;
    pthread_mutex_unlock(&join_lock);
}
RPState rp_snapshot(void) { pthread_mutex_lock(&lock); RPState s=state; pthread_mutex_unlock(&lock); return s; }
