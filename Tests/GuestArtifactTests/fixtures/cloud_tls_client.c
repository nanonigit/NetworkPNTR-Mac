#include "ArtexCloudTLS.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    int cancel_after_first_chunk;
    uint64_t cancel_at;
    unsigned chunks;
    size_t bytes_received;
    size_t finish_after;
} fixture_state;

static uint64_t now_ms(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000 + (uint64_t)time.tv_nsec / 1000000;
}

static int cancelled(void *opaque) {
    fixture_state *state = opaque;
    return state->cancel_at && now_ms() >= state->cancel_at;
}

static int receive(void *opaque, const uint8_t *bytes, size_t count) {
    fixture_state *state = opaque;
    if (!state->chunks++ && state->cancel_after_first_chunk) state->cancel_at = now_ms() + 75;
    if (fwrite(bytes, 1, count, stdout) != count) return 1;
    state->bytes_received += count;
    return state->finish_after && state->bytes_received == state->finish_after ? 2 : 0;
}

int main(int argc, char **argv) {
    if (argc != 7) return 64;
    uint32_t deadline = (uint32_t)strtoul(argv[4], NULL, 10);
    artx_cloud_options options = {
        .hostname = argv[1],
        .numeric_ip = "127.0.0.1",
        .port = (uint16_t)strtoul(argv[2], NULL, 10),
        .connect_timeout_ms = deadline,
        .total_timeout_ms = deadline,
        .maximum_response_bytes = (size_t)strtoul(argv[5], NULL, 10)
    };
    fixture_state state = { .cancel_after_first_chunk = strcmp(argv[6], "cancel-after-chunk") == 0 };
    if (strcmp(argv[6], "finish-at-boundary") == 0)
        state.finish_after = sizeof("HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\nfirst-second") - 1;
    if (strcmp(argv[6], "cancel-dial") == 0) state.cancel_at = now_ms() + 500;
    const char *header = "GET /v1/models HTTP/1.1\r\nHost: egress.test\r\nConnection: close\r\n\r\n";
    const char *body = "";
    size_t body_size = 0;
    char *allocated = NULL;
    if (strcmp(argv[6], "post") == 0) {
        header = "POST /v1/chat/completions HTTP/1.1\r\nHost: egress.test\r\nContent-Length: 19\r\nConnection: close\r\n\r\n";
        body = "{\"model\":\"fixture\"}";
        body_size = strlen(body);
    } else if (strcmp(argv[6], "large-post") == 0) {
        header = "POST /v1/chat/completions HTTP/1.1\r\nHost: egress.test\r\nContent-Length: 8388608\r\nConnection: close\r\n\r\n";
        body_size = 8 * 1024 * 1024;
        allocated = malloc(body_size);
        if (!allocated) return 65;
        memset(allocated, 'q', body_size);
        body = allocated;
    }
    artx_cloud_result result = artx_cloud_tls_fixture(
        &options, strcmp(argv[3], "-") == 0 ? NULL : argv[3],
        (const uint8_t *)header, strlen(header), (const uint8_t *)body, body_size, cancelled, receive, &state);
    free(allocated);
    fprintf(stderr, "result=%d chunks=%u\n", result, state.chunks);
    return result;
}
