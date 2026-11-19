#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fs.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

static unsigned char buffer[1024 * 1024];

static ssize_t read_bytes(int fd, void *out, size_t count) {
    ssize_t result;
    do { result = read(fd, out, count); } while (result < 0 && errno == EINTR);
    return result;
}

static int check_disk(int fd) {
    struct stat metadata;
    uint64_t remaining;
    if (fstat(fd, &metadata) != 0 || !S_ISBLK(metadata.st_mode) ||
        ioctl(fd, BLKGETSIZE64, &remaining) != 0 || remaining == 0) {
        return 3;
    }
    while (remaining > 0) {
        size_t count = remaining > sizeof(buffer) ? sizeof(buffer) : (size_t)remaining;
        ssize_t got = read_bytes(fd, buffer, count);
        if (got <= 0) { return 3; }
        for (ssize_t index = 0; index < got; ++index) {
            if (buffer[index] != 0) { return 2; }
        }
        remaining -= (uint64_t)got;
    }
    return read_bytes(fd, buffer, 1) == 0 ? 0 : 3;
}

int main(void) {
    int fd = open("/dev/vdb", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) { return 3; }
    int result = check_disk(fd);
    return close(fd) == 0 ? result : 3;
}
