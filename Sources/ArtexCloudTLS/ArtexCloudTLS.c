#include "ArtexCloudTLS.h"

#include <arpa/inet.h>
#include <curl/curl.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct {
    int family;
    uint16_t port;
    unsigned char bytes[16];
} artx_peer;

typedef struct {
    CURL *easy;
    curl_socket_t socket;
    uint64_t deadline;
    artx_cloud_cancelled cancelled;
    void *context;
} artx_exchange;

static pthread_once_t curl_once = PTHREAD_ONCE_INIT;
static CURLcode curl_init_result = CURLE_FAILED_INIT;

static void initialize_curl(void) {
    curl_init_result = curl_global_init(CURL_GLOBAL_DEFAULT);
}

static uint64_t monotonic_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}

static int peer_matches(const artx_peer *expected, const struct sockaddr *address, size_t size) {
    if (size < sizeof(*address) || address->sa_family != expected->family) return 0;
    if (expected->family == AF_INET && size >= sizeof(struct sockaddr_in)) {
        const struct sockaddr_in *peer = (const struct sockaddr_in *)address;
        return ntohs(peer->sin_port) == expected->port &&
            memcmp(&peer->sin_addr, expected->bytes, 4) == 0;
    }
    if (expected->family == AF_INET6 && size >= sizeof(struct sockaddr_in6)) {
        const struct sockaddr_in6 *peer = (const struct sockaddr_in6 *)address;
        return peer->sin6_scope_id == 0 && ntohs(peer->sin6_port) == expected->port &&
            memcmp(&peer->sin6_addr, expected->bytes, 16) == 0;
    }
    return 0;
}

static curl_socket_t open_pinned_socket(void *context, curlsocktype purpose, struct curl_sockaddr *address) {
    if (purpose != CURLSOCKTYPE_IPCXN || address->socktype != SOCK_STREAM ||
        !peer_matches(context, &address->addr, address->addrlen)) return CURL_SOCKET_BAD;
    const curl_socket_t fd = socket(address->family, address->socktype, address->protocol);
    if (fd == CURL_SOCKET_BAD) return fd;
    const int one = 1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) != 0 ||
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) {
        close(fd);
        return CURL_SOCKET_BAD;
    }
    return fd;
}

static int active_peer_matches(artx_exchange *exchange, const artx_peer *expected) {
    struct sockaddr_storage address;
    socklen_t length = sizeof(address);
    return curl_easy_getinfo(exchange->easy, CURLINFO_ACTIVESOCKET, &exchange->socket) == CURLE_OK &&
        exchange->socket != CURL_SOCKET_BAD &&
        getpeername(exchange->socket, (struct sockaddr *)&address, &length) == 0 &&
        peer_matches(expected, (struct sockaddr *)&address, length);
}

static artx_cloud_result guard_exchange(const artx_exchange *exchange) {
    if (exchange->cancelled(exchange->context)) return ARTX_CLOUD_CANCELLED;
    if (monotonic_ms() >= exchange->deadline) return ARTX_CLOUD_TIMED_OUT;
    return ARTX_CLOUD_OK;
}

static int poll_interval(uint64_t deadline) {
    const uint64_t now = monotonic_ms();
    if (now >= deadline) return 0;
    const uint64_t remaining = deadline - now;
    return remaining < 25 ? (int)remaining : 25;
}

static artx_cloud_result connect_tls(CURLM *multi, artx_exchange *exchange) {
    for (;;) {
        artx_cloud_result result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        int running = 0;
        if (curl_multi_perform(multi, &running) != CURLM_OK) return ARTX_CLOUD_CONNECT_FAILED;
        if (!running) break;
        if (curl_multi_poll(multi, NULL, 0, poll_interval(exchange->deadline), NULL) != CURLM_OK) {
            return ARTX_CLOUD_CONNECT_FAILED;
        }
    }
    int remaining;
    CURLMsg *message = curl_multi_info_read(multi, &remaining);
    if (!message || message->msg != CURLMSG_DONE) return ARTX_CLOUD_CONNECT_FAILED;
    switch (message->data.result) {
    case CURLE_OK: return guard_exchange(exchange);
    case CURLE_OPERATION_TIMEDOUT: return ARTX_CLOUD_TIMED_OUT;
    default: return ARTX_CLOUD_CONNECT_FAILED;
    }
}

static artx_cloud_result wait_socket(const artx_exchange *exchange, short events) {
    artx_cloud_result result = guard_exchange(exchange);
    if (result != ARTX_CLOUD_OK) return result;
    struct pollfd socket = { .fd = exchange->socket, .events = events };
    int ready = poll(&socket, 1, poll_interval(exchange->deadline));
    if ((ready < 0 && errno != EINTR) || (socket.revents & POLLNVAL)) return ARTX_CLOUD_IO_FAILED;
    return ARTX_CLOUD_OK;
}

static artx_cloud_result send_bytes(const artx_exchange *exchange, const uint8_t *bytes, size_t length) {
    while (length > 0) {
        artx_cloud_result result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        size_t sent = 0;
        CURLcode code = curl_easy_send(exchange->easy, bytes, length, &sent);
        if (code == CURLE_AGAIN) {
            result = wait_socket(exchange, POLLOUT);
            if (result != ARTX_CLOUD_OK) return result;
            continue;
        }
        if (code != CURLE_OK || !sent || sent > length) return ARTX_CLOUD_IO_FAILED;
        bytes += sent;
        length -= sent;
    }
    return ARTX_CLOUD_OK;
}

static artx_cloud_result receive_response(const artx_exchange *exchange, size_t remaining, artx_cloud_receive receive) {
    uint8_t buffer[16384];
    for (;;) {
        artx_cloud_result result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        size_t count = 0;
        CURLcode code = curl_easy_recv(exchange->easy, buffer, sizeof(buffer), &count);
        if (code == CURLE_AGAIN) {
            result = wait_socket(exchange, POLLIN);
            if (result != ARTX_CLOUD_OK) return result;
            continue;
        }
        if (code != CURLE_OK) return ARTX_CLOUD_IO_FAILED;
        result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK || !count) return result;
        if (count > remaining) return ARTX_CLOUD_RESPONSE_LIMIT;
        if (receive(exchange->context, buffer, count)) return ARTX_CLOUD_SINK_ABORTED;
        remaining -= count;
    }
}

static int safe_hostname(const char *name) {
    if (!name || !*name || strlen(name) > 253) return 0;
    return strspn(name, "abcdefghijklmnopqrstuvwxyz0123456789.-") == strlen(name) &&
        name[0] != '.' && name[strlen(name) - 1] != '.';
}

static artx_cloud_result tls_exchange(
    const artx_cloud_options *options, const char *fixture_ca,
    const uint8_t *header, size_t header_size, const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context
) {
    if (!options || !safe_hostname(options->hostname) || !options->numeric_ip || !options->port ||
        !options->connect_timeout_ms || options->connect_timeout_ms > options->total_timeout_ms ||
        !options->maximum_response_bytes || !header || !header_size || header_size > 8192 ||
        (body_size && !body) || body_size > 16 * 1024 * 1024 || !cancelled || !receive) return ARTX_CLOUD_INVALID;

    artx_peer expected = { .family = AF_INET, .port = options->port };
    if (inet_pton(AF_INET, options->numeric_ip, expected.bytes) != 1) {
        expected.family = AF_INET6;
        if (inet_pton(AF_INET6, options->numeric_ip, expected.bytes) != 1) return ARTX_CLOUD_INVALID;
    }
    artx_exchange exchange = {
        .socket = CURL_SOCKET_BAD, .deadline = monotonic_ms() + options->total_timeout_ms,
        .cancelled = cancelled, .context = context
    };
    artx_cloud_result result = guard_exchange(&exchange);
    if (result != ARTX_CLOUD_OK) return result;

    char url[280], rule[320];
    const int url_size = snprintf(url, sizeof(url), "https://%s:%u/", options->hostname, (unsigned)options->port);
    const char *format = expected.family == AF_INET6 ? "%s:%u:[%s]" : "%s:%u:%s";
    const int rule_size = snprintf(rule, sizeof(rule), format, options->hostname, (unsigned)options->port, options->numeric_ip);
    if (url_size < 0 || (size_t)url_size >= sizeof(url) || rule_size < 0 || (size_t)rule_size >= sizeof(rule)) {
        return ARTX_CLOUD_INVALID;
    }
    if (pthread_once(&curl_once, initialize_curl) != 0 || curl_init_result != CURLE_OK) return ARTX_CLOUD_CONNECT_FAILED;
    exchange.easy = curl_easy_init();
    CURLM *multi = curl_multi_init();
    struct curl_slist *addresses = curl_slist_append(NULL, rule);
    int added = 0;
    result = ARTX_CLOUD_CONNECT_FAILED;
    if (!exchange.easy || !multi || !addresses) goto cleanup;

#define SET_OPTION(option, value) if (curl_easy_setopt(exchange.easy, option, value) != CURLE_OK) goto cleanup
    SET_OPTION(CURLOPT_URL, url);
    SET_OPTION(CURLOPT_RESOLVE, addresses);
    SET_OPTION(CURLOPT_PROXY, "");
    SET_OPTION(CURLOPT_FOLLOWLOCATION, 0L);
    SET_OPTION(CURLOPT_CONNECT_ONLY, 1L);
    SET_OPTION(CURLOPT_CONNECTTIMEOUT_MS, (long)options->connect_timeout_ms);
    SET_OPTION(CURLOPT_TIMEOUT_MS, (long)options->total_timeout_ms);
    SET_OPTION(CURLOPT_NOSIGNAL, 1L);
    SET_OPTION(CURLOPT_SSL_VERIFYPEER, 1L);
    SET_OPTION(CURLOPT_SSL_VERIFYHOST, 2L);
    SET_OPTION(CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);
    SET_OPTION(CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
    SET_OPTION(CURLOPT_OPENSOCKETFUNCTION, open_pinned_socket);
    SET_OPTION(CURLOPT_OPENSOCKETDATA, &expected);
    if (fixture_ca) {
        SET_OPTION(CURLOPT_CAINFO, fixture_ca);
    }
#undef SET_OPTION

    if (curl_multi_add_handle(multi, exchange.easy) != CURLM_OK) goto cleanup;
    added = 1;
    result = connect_tls(multi, &exchange);
    if (result != ARTX_CLOUD_OK) goto cleanup;
    if (!active_peer_matches(&exchange, &expected)) {
        result = ARTX_CLOUD_CONNECT_FAILED;
        goto cleanup;
    }
    result = send_bytes(&exchange, header, header_size);
    if (result != ARTX_CLOUD_OK) goto cleanup;
    result = send_bytes(&exchange, body, body_size);
    if (result != ARTX_CLOUD_OK) goto cleanup;
    result = receive_response(&exchange, options->maximum_response_bytes, receive);

cleanup:
    if (added) curl_multi_remove_handle(multi, exchange.easy);
    if (exchange.easy) curl_easy_cleanup(exchange.easy);
    if (multi) curl_multi_cleanup(multi);
    curl_slist_free_all(addresses);
    return result;
}

artx_cloud_result artx_cloud_tls_exchange(
    const artx_cloud_options *options,
    const uint8_t *header, size_t header_size, const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context
) {
    return tls_exchange(options, NULL, header, header_size, body, body_size, cancelled, receive, context);
}

#ifdef ARTEX_CLOUD_TLS_FIXTURE
artx_cloud_result artx_cloud_tls_fixture(
    const artx_cloud_options *options, const char *ca_path,
    const uint8_t *header, size_t header_size, const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context
) {
    return tls_exchange(options, ca_path, header, header_size, body, body_size, cancelled, receive, context);
}
#endif
