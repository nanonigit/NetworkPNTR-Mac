#include "ArtexCloudTLS.h"

#include <Security/SecCertificate.h>
#include <Security/SecPolicy.h>
#include <Security/SecTrust.h>
#include <Security/SecureTransport.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifdef ARTEX_CLOUD_TLS_FIXTURE
#include <stdio.h>
#endif

// SecureTransport is the macOS API that permits an explicit certificate
// evaluation on a caller-owned, already pinned socket.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

typedef union {
    struct sockaddr generic;
    struct sockaddr_in ipv4;
    struct sockaddr_in6 ipv6;
} artx_peer;

typedef struct {
    int socket;
    SSLContextRef tls;
    short waiting_for;
    artx_cloud_result interrupted;
    uint64_t deadline;
    artx_cloud_cancelled cancelled;
    void *context;
} artx_exchange;

static uint64_t monotonic_ms(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1000000;
}

static socklen_t make_peer(artx_peer *peer, const artx_cloud_options *options) {
    if (inet_pton(AF_INET, options->numeric_ip, &peer->ipv4.sin_addr) == 1) {
        peer->ipv4.sin_family = AF_INET;
        peer->ipv4.sin_port = htons(options->port);
        peer->ipv4.sin_len = sizeof(peer->ipv4);
        return sizeof(peer->ipv4);
    }
    if (inet_pton(AF_INET6, options->numeric_ip, &peer->ipv6.sin6_addr) == 1) {
        peer->ipv6.sin6_family = AF_INET6;
        peer->ipv6.sin6_port = htons(options->port);
        peer->ipv6.sin6_len = sizeof(peer->ipv6);
        return sizeof(peer->ipv6);
    }
    return 0;
}

static int active_peer_matches(int fd, const artx_peer *expected) {
    artx_peer actual = {0};
    socklen_t size = sizeof(actual);
    if (getpeername(fd, &actual.generic, &size) != 0 ||
        actual.generic.sa_family != expected->generic.sa_family) return 0;
    if (actual.generic.sa_family == AF_INET) {
        return size == sizeof(actual.ipv4) && actual.ipv4.sin_port == expected->ipv4.sin_port &&
            actual.ipv4.sin_addr.s_addr == expected->ipv4.sin_addr.s_addr;
    }
    return size == sizeof(actual.ipv6) && actual.ipv6.sin6_scope_id == 0 &&
        actual.ipv6.sin6_port == expected->ipv6.sin6_port &&
        memcmp(&actual.ipv6.sin6_addr, &expected->ipv6.sin6_addr, sizeof(actual.ipv6.sin6_addr)) == 0;
}

static artx_cloud_result guard_exchange(const artx_exchange *exchange) {
    if (exchange->interrupted != ARTX_CLOUD_OK) return exchange->interrupted;
    if (exchange->cancelled(exchange->context)) return ARTX_CLOUD_CANCELLED;
    if (monotonic_ms() >= exchange->deadline) return ARTX_CLOUD_TIMED_OUT;
    return ARTX_CLOUD_OK;
}

static artx_cloud_result wait_socket(const artx_exchange *exchange, short events) {
    if (!events) return ARTX_CLOUD_IO_FAILED;
    for (;;) {
        artx_cloud_result result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        const uint64_t now = monotonic_ms();
        if (now >= exchange->deadline) return ARTX_CLOUD_TIMED_OUT;
        const uint64_t remaining = exchange->deadline - now;
        struct pollfd socket = { .fd = exchange->socket, .events = events };
        int ready = poll(&socket, 1, remaining < 25 ? (int)remaining : 25);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0 || (socket.revents & POLLNVAL)) return ARTX_CLOUD_IO_FAILED;
        if (ready > 0) return guard_exchange(exchange);
    }
}

static artx_cloud_result connect_socket(artx_exchange *exchange, const artx_peer *peer,
                                        socklen_t length) {
    exchange->socket = socket(peer->generic.sa_family, SOCK_STREAM, IPPROTO_TCP);
    const int fd = exchange->socket;
    const int one = 1;
    if (fd < 0 || fcntl(fd, F_SETFD, FD_CLOEXEC) != 0 || fcntl(fd, F_SETFL, O_NONBLOCK) != 0 ||
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) return ARTX_CLOUD_CONNECT_FAILED;
    if (connect(fd, &peer->generic, length) != 0) {
        if (errno != EINPROGRESS && errno != EINTR) return ARTX_CLOUD_CONNECT_FAILED;
        artx_cloud_result result = wait_socket(exchange, POLLOUT);
        if (result != ARTX_CLOUD_OK) return result;
        int error;
        socklen_t size = sizeof(error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) != 0 || error) return ARTX_CLOUD_CONNECT_FAILED;
    }
    if (!active_peer_matches(fd, peer)) return ARTX_CLOUD_CONNECT_FAILED;
    return guard_exchange(exchange);
}

static OSStatus socket_read(SSLConnectionRef connection, void *buffer, size_t *length) {
    artx_exchange *exchange = (artx_exchange *)connection;
    exchange->interrupted = guard_exchange(exchange);
    if (exchange->interrupted != ARTX_CLOUD_OK) {
        *length = 0;
        return errSSLClosedAbort;
    }
    const size_t requested = *length;
    const ssize_t received = recv(exchange->socket, buffer, requested, 0);
    *length = received > 0 ? (size_t)received : 0;
    if (received == 0) return errSSLClosedNoNotify;
    if (received < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) return errSSLClosedAbort;
    if (*length == requested) return noErr;
    exchange->waiting_for |= POLLIN;
    return errSSLWouldBlock;
}

static OSStatus socket_write(SSLConnectionRef connection, const void *buffer, size_t *length) {
    artx_exchange *exchange = (artx_exchange *)connection;
    exchange->interrupted = guard_exchange(exchange);
    if (exchange->interrupted != ARTX_CLOUD_OK) {
        *length = 0;
        return errSSLClosedAbort;
    }
    const size_t requested = *length;
    const ssize_t sent = send(exchange->socket, buffer, requested, 0);
    *length = sent > 0 ? (size_t)sent : 0;
    if (sent < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) return errSSLClosedAbort;
    if (*length == requested) return noErr;
    exchange->waiting_for |= POLLOUT;
    return errSSLWouldBlock;
}

static int validate_server(SSLContextRef tls, CFStringRef hostname, SecCertificateRef fixture_anchor) {
    SecTrustRef trust = NULL;
    if (SSLCopyPeerTrust(tls, &trust) != noErr || !trust) {
        if (trust) CFRelease(trust);
        return 0;
    }

    SecPolicyRef ssl = SecPolicyCreateSSL(true, hostname);
    SecPolicyRef offline = SecPolicyCreateRevocation(kSecRevocationUseAnyAvailableMethod | kSecRevocationNetworkAccessDisabled);
    const void *values[] = {ssl, offline};
    CFArrayRef policies = ssl && offline ? CFArrayCreate(NULL, values, 2, &kCFTypeArrayCallBacks) : NULL;
    int allowed = policies && SecTrustSetPolicies(trust, policies) == errSecSuccess &&
        SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess;

    if (allowed && fixture_anchor) {
        const void *anchors[] = {fixture_anchor};
        CFArrayRef array = CFArrayCreate(NULL, anchors, 1, &kCFTypeArrayCallBacks);
        allowed = array && SecTrustSetAnchorCertificates(trust, array) == errSecSuccess &&
            SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess;
        if (array) CFRelease(array);
    }
    allowed = allowed && SecTrustEvaluateWithError(trust, NULL);
    if (policies) CFRelease(policies);
    if (offline) CFRelease(offline);
    if (ssl) CFRelease(ssl);
    CFRelease(trust);
    return allowed;
}

static artx_cloud_result connect_tls(artx_exchange *exchange, const char *hostname,
                                     SecCertificateRef fixture_anchor) {
    SSLContextRef tls = SSLCreateContext(NULL, kSSLClientSide, kSSLStreamType);
    exchange->tls = tls;
    if (!tls || SSLSetIOFuncs(tls, socket_read, socket_write) != noErr ||
        SSLSetConnection(tls, exchange) != noErr ||
        SSLSetPeerDomainName(tls, hostname, strlen(hostname)) != noErr ||
        SSLSetProtocolVersionMin(tls, kTLSProtocol12) != noErr ||
        SSLSetProtocolVersionMax(tls, kTLSProtocol12) != noErr ||
        SSLSetSessionOption(tls, kSSLSessionOptionBreakOnServerAuth, true) != noErr ||
        SSLSetSessionOption(tls, kSSLSessionOptionFalseStart, false) != noErr ||
        SSLSetSessionOption(tls, kSSLSessionOptionAllowRenegotiation, false) != noErr) {
        return ARTX_CLOUD_CONNECT_FAILED;
    }

    CFStringRef name = CFStringCreateWithCString(NULL, hostname, kCFStringEncodingASCII);
    if (!name) return ARTX_CLOUD_CONNECT_FAILED;
    int verified = 0;
    artx_cloud_result result;
    for (;;) {
        result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) break;
        exchange->waiting_for = 0;
        OSStatus status = SSLHandshake(tls);
        result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) break;
        if (status == errSSLServerAuthCompleted && !verified && validate_server(tls, name, fixture_anchor)) {
            verified = 1;
            continue;
        }
        if (status != errSSLWouldBlock) {
            result = status == noErr && verified ? guard_exchange(exchange) : ARTX_CLOUD_CONNECT_FAILED;
            break;
        }
        result = wait_socket(exchange, exchange->waiting_for);
        if (result != ARTX_CLOUD_OK) break;
    }
    CFRelease(name);
    return result;
}

static artx_cloud_result send_bytes(artx_exchange *exchange, const uint8_t *bytes, size_t remaining) {
    if (!remaining) return ARTX_CLOUD_OK;
    for (;;) {
        artx_cloud_result result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        exchange->waiting_for = 0;
        size_t written = 0;
        const size_t count = remaining < 16384 ? remaining : 16384;
        // A would-block result may queue all plaintext. A zero-length retry
        // drains that queue before the worker starts reading the response.
        OSStatus status = SSLWrite(exchange->tls, bytes, count, &written);
        result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        if (written > count) return ARTX_CLOUD_IO_FAILED;
        bytes += written;
        remaining -= written;
        if (status == noErr) {
            if (!remaining) return ARTX_CLOUD_OK;
            if (!written) return ARTX_CLOUD_IO_FAILED;
            continue;
        }
        if (status != errSSLWouldBlock) return ARTX_CLOUD_IO_FAILED;
        result = wait_socket(exchange, exchange->waiting_for);
        if (result != ARTX_CLOUD_OK) return result;
    }
}

static artx_cloud_result receive_response(artx_exchange *exchange, size_t remaining, artx_cloud_receive receive) {
    uint8_t buffer[16384];
    for (;;) {
        artx_cloud_result result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        exchange->waiting_for = 0;
        size_t count = 0;
        OSStatus status = SSLRead(exchange->tls, buffer, sizeof(buffer), &count);
        result = guard_exchange(exchange);
        if (result != ARTX_CLOUD_OK) return result;
        if (status != noErr && status != errSSLWouldBlock && status != errSSLClosedGraceful) return ARTX_CLOUD_IO_FAILED;
        if (status == noErr && !count) return ARTX_CLOUD_IO_FAILED;
        if (count > remaining || count > sizeof(buffer)) return ARTX_CLOUD_RESPONSE_LIMIT;
        if (count) {
            const int action = receive(exchange->context, buffer, count);
            if (action == 2) return guard_exchange(exchange);
            if (action != 0) return ARTX_CLOUD_SINK_ABORTED;
        }
        remaining -= count;
        if (status == errSSLClosedGraceful) return ARTX_CLOUD_OK;
        if (status == errSSLWouldBlock) {
            result = wait_socket(exchange, exchange->waiting_for);
            if (result != ARTX_CLOUD_OK) return result;
        }
    }
}

static int safe_hostname(const char *name) {
    if (!name || !*name || strlen(name) > 253) return 0;
    return strspn(name, "abcdefghijklmnopqrstuvwxyz0123456789.-") == strlen(name) &&
        name[0] != '.' && name[strlen(name) - 1] != '.';
}

static artx_cloud_result tls_exchange(
    const artx_cloud_options *options, SecCertificateRef fixture_anchor,
    const uint8_t *header, size_t header_size, const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context
) {
    if (!options || !safe_hostname(options->hostname) || !options->numeric_ip || !options->port ||
        !options->connect_timeout_ms || options->connect_timeout_ms > options->total_timeout_ms ||
        !options->maximum_response_bytes || !header || !header_size || header_size > 8192 ||
        (body_size && !body) || body_size > 16 * 1024 * 1024 || !cancelled || !receive) return ARTX_CLOUD_INVALID;

    artx_peer expected = {0};
    const socklen_t length = make_peer(&expected, options);
    if (!length) return ARTX_CLOUD_INVALID;
    const uint64_t started = monotonic_ms();
    artx_exchange exchange = {
        .socket = -1, .deadline = started + options->connect_timeout_ms,
        .cancelled = cancelled, .context = context
    };
    artx_cloud_result result = guard_exchange(&exchange);
    if (result == ARTX_CLOUD_OK) result = connect_socket(&exchange, &expected, length);
    if (result == ARTX_CLOUD_OK) result = connect_tls(&exchange, options->hostname, fixture_anchor);
    if (result == ARTX_CLOUD_OK && !active_peer_matches(exchange.socket, &expected)) result = ARTX_CLOUD_CONNECT_FAILED;
    exchange.deadline = started + options->total_timeout_ms;
    if (result == ARTX_CLOUD_OK) result = send_bytes(&exchange, header, header_size);
    if (result == ARTX_CLOUD_OK) result = send_bytes(&exchange, body, body_size);
    if (result == ARTX_CLOUD_OK) result = receive_response(&exchange, options->maximum_response_bytes, receive);

    if (exchange.tls) {
        if (result == ARTX_CLOUD_OK) (void)SSLClose(exchange.tls);
        CFRelease(exchange.tls);
    }
    if (exchange.socket >= 0) close(exchange.socket);
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
static SecCertificateRef read_anchor(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    uint8_t bytes[16384];
    size_t count = fread(bytes, 1, sizeof(bytes), file);
    const int valid = count && count < sizeof(bytes) && feof(file) && !ferror(file);
    fclose(file);
    if (!valid) return NULL;
    CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)count);
    SecCertificateRef anchor = data ? SecCertificateCreateWithData(NULL, data) : NULL;
    if (data) CFRelease(data);
    return anchor;
}

artx_cloud_result artx_cloud_tls_fixture(
    const artx_cloud_options *options, const char *ca_path,
    const uint8_t *header, size_t header_size, const uint8_t *body, size_t body_size,
    artx_cloud_cancelled cancelled, artx_cloud_receive receive, void *context
) {
    SecCertificateRef anchor = ca_path ? read_anchor(ca_path) : NULL;
    if (ca_path && !anchor) return ARTX_CLOUD_INVALID;
    artx_cloud_result result = tls_exchange(options, anchor, header, header_size, body, body_size, cancelled, receive, context);
    if (anchor) CFRelease(anchor);
    return result;
}
#endif

#pragma clang diagnostic pop
