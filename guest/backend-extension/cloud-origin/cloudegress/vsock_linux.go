package cloudegress

import (
	"context"
	"errors"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

const hostPort = 8790

func dialHost(ctx context.Context, deadline time.Time) (connection, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	fd, err := unix.Socket(unix.AF_VSOCK, unix.SOCK_STREAM|unix.SOCK_NONBLOCK|unix.SOCK_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	owned := true
	defer func() {
		if owned {
			_ = unix.Close(fd)
		}
	}()
	err = unix.Connect(fd, &unix.SockaddrVM{CID: unix.VMADDR_CID_HOST, Port: hostPort})
	if err != nil && !errors.Is(err, unix.EINPROGRESS) && !errors.Is(err, unix.EINTR) {
		return nil, err
	}
	if err != nil {
		for {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			remaining := time.Until(deadline)
			if remaining <= 0 {
				return nil, context.DeadlineExceeded
			}
			fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLOUT}}
			ready, err := unix.Poll(fds, int(max(time.Millisecond, min(25*time.Millisecond, remaining))/time.Millisecond))
			if errors.Is(err, unix.EINTR) {
				continue
			}
			if err != nil {
				return nil, err
			}
			if ready > 0 {
				status, err := unix.GetsockoptInt(fd, unix.SOL_SOCKET, unix.SO_ERROR)
				if err != nil {
					return nil, err
				}
				if status != 0 {
					return nil, unix.Errno(status)
				}
				break
			}
		}
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if time.Now().After(deadline) {
		return nil, context.DeadlineExceeded
	}
	file := os.NewFile(uintptr(fd), "cloud-egress-vsock")
	if file == nil {
		return nil, unix.EBADF
	}
	owned = false
	return file, nil
}
