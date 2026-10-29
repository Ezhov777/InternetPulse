#include "../Sources/NetworkEngine.h"
#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <assert.h>
#include <pthread.h>
#include <math.h>
static void *join_worker(void *unused) { (void)unused;rp_join();return NULL; }
static double now(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9; }
int main(int argc,char **argv) {
    const char *download=argc>1 ? argv[1] : "http://127.0.0.1:18762/data";
    const char *upload=argc>2 ? argv[2] : "http://127.0.0.1:18762/upload";
    assert(!rp_start_parallel(download,upload,NAN,1,4,0));
    assert(!rp_start_parallel(download,upload,1,1,17,0));
    assert(rp_start_parallel(download,upload,1,0.5,4,0));
    sleep(10);
    RPState s=rp_snapshot();
    printf("10s: down=%llu up=%llu errors=%d http=%.1fms\n",(unsigned long long)s.downloaded,(unsigned long long)s.uploaded,s.errors,s.latency_ms);
    assert(s.downloaded>750000 && s.downloaded<1700000);
    assert(s.uploaded>400000 && s.uploaded<1000000);
    assert(s.errors==0);
    double start=now();rp_request_stop();
    pthread_t a,b;
    assert(!pthread_create(&a,NULL,join_worker,NULL));
    assert(!pthread_create(&b,NULL,join_worker,NULL));
    pthread_join(a,NULL);pthread_join(b,NULL);
    printf("Stop: %.2fs\n",now()-start);assert(now()-start<9);
    s=rp_snapshot();sleep(1);RPState after=rp_snapshot();
    assert(after.downloaded==s.downloaded && after.uploaded==s.uploaded);
    assert(rp_start("http://127.0.0.1:18762/error",upload,1,0));
    sleep(8);s=rp_snapshot();
    printf("503: errors=%d bytes=%llu\n",s.errors,(unsigned long long)s.downloaded);
    assert(s.errors>=2 && s.errors<=4 && s.downloaded==0);
    rp_request_stop();rp_join();
    puts("PASS: four streams per direction, aggregate limits, concurrent stop, restart, HTTP errors and retry backoff");
}
