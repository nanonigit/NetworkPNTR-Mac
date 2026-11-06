#ifndef ARTEX_CLOUD_TLS_H
#define ARTEX_CLOUD_TLS_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    ARTX_CLOUD_OK,
    ARTX_CLOUD_INVALID,
    ARTX_CLOUD_CONNECT_FAILED,
    ARTX_CLOUD_IO_FAILED,
    ARTX_CLOUD_CANCELLED,
    ARTX_CLOUD_TIMED_OUT,
    ARTX_CLOUD_RESPONSE_LIMIT,
    ARTX_CLOUD_SINK_ABORTED
} artx_cloud_result;

typedef struct {
    const char *hostname;
    const char *numeric_ip;
    uint16_t port;
    uint32_t connect_timeout_ms;
    uint32_t total_timeout_ms;
    size_t maximum_response_bytes;
} artx_cloud_options;

typedef int (*artx_cloud_cancelled)(void *context);
// Return 0 to keep reading, 1 to abort, or 2 when the HTTP parser has
// accepted the complete response in this buffer.
typedef int (*artx_cloud_receive)(void *context, const uint8_t *bytes, size_t count);

// Synchronous. Callbacks run on the calling worker. The Swift policy owns
// hostname and address admission before entering this transport.
artx_cloud_result artx_cloud_tls_exchange(
    const artx_cloud_options *options,
    const uint8_t *header, size_t header_size,
    const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context);

#ifdef ARTEX_CLOUD_TLS_FIXTURE
// Fixture-only trust anchor. It is excluded from application builds.
artx_cloud_result artx_cloud_tls_fixture(
    const artx_cloud_options *options, const char *ca_path,
    const uint8_t *header, size_t header_size, const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context);
#endif

#endif
