#define main checker_main
#include "check.c"
#undef main
#include <assert.h>
#include <stdarg.h>
#include <string.h>

static unsigned scenario, calls, offset;

int __wrap_fstat(int fd, struct stat *st) {
    assert(fd == 7);
    st->st_mode = scenario == 1 ? S_IFREG : S_IFBLK;
    return scenario == 2 ? -1 : 0;
}

int __wrap_ioctl(int fd, unsigned long request, ...) {
    assert(fd == 7 && request == BLKGETSIZE64);
    va_list args;
    va_start(args, request);
    *va_arg(args, uint64_t *) = scenario == 3 ? 0 : 8;
    va_end(args);
    return scenario == 4 ? -1 : 0;
}

ssize_t __wrap_read(int fd, void *data, size_t count) {
    assert(fd == 7 && count > 0);
    calls++;
    if (scenario == 5 && calls == 1) { errno = EINTR; return -1; }
    if (scenario == 6) { errno = EIO; return -1; }
    if (scenario == 7 && offset == 3) { return 0; }
    if (offset == 8) { return scenario == 8 ? 1 : 0; }
    unsigned n = count > 3 ? 3 : (unsigned)count;
    memset(data, 0, n);
    offset += n;
    if (scenario == 9 && offset == 8) { ((unsigned char *)data)[n - 1] = 1; }
    return n;
}

int main(void) {
    const int expected[] = {0, 3, 3, 3, 3, 0, 3, 3, 3, 2};
    for (scenario = 0; scenario < sizeof(expected) / sizeof(expected[0]); scenario++) {
        calls = offset = 0;
        assert(check_disk(7) == expected[scenario]);
    }
    return 0;
}
