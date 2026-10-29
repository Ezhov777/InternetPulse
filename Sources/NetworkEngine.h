#ifndef NETWORK_ENGINE_H
#define NETWORK_ENGINE_H
#include <stdint.h>
typedef struct RPState {
    uint64_t downloaded, uploaded;
    int errors;
    double latency_ms;
    uint64_t event_id;
    char message[256];
} RPState;
int rp_start(const char *download_url, const char *upload_url, double down_mbps, double up_mbps);
int rp_start_parallel(const char *download_url, const char *upload_url, double down_mbps, double up_mbps, int streams, int unlimited);
void rp_request_stop(void);
void rp_join(void);
RPState rp_snapshot(void);
#endif
