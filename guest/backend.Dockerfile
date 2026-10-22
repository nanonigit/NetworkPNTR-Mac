FROM alpine:3.22.7@sha256:e9f2de928efcc1b53d0948e684b4f490315f280de6044844ec0ff26c0b44d3cf
RUN apk add --no-cache postgresql16=16.15-r0 postgresql16-client=16.15-r0 su-exec=0.2-r3 e2fsprogs=1.47.2-r2 python3 curl ca-certificates git jq ripgrep nmap bind-tools netcat-openbsd whois nodejs npm \
    && mkdir -p /opt/artex /state /run /proc /sys /dev /tmp \
    && ln -s /state/auth/jwt.key /opt/artex/jwt.key
COPY artex /opt/artex/artex
COPY skills/ /opt/artex/skills/
COPY vsock_relay.py check_blank_disk.py /opt/artex-mac/
COPY backend-init /sbin/artex-init
COPY backend-packages.lock /expected-packages.lock
RUN apk info -vv > /actual-packages.lock && cmp -s /actual-packages.lock /expected-packages.lock
RUN chmod 755 /sbin/artex-init /opt/artex/artex \
    && mkdir /rootfs \
    && cp -a /bin /etc /lib /usr /sbin /opt /rootfs/ \
    && mkdir -p /rootfs/state /rootfs/run /rootfs/proc /rootfs/sys /rootfs/dev /rootfs/tmp /rootfs/root /rootfs/var/lib /rootfs/var/log \
    && apk info -vv > /rootfs/opt/artex-mac/packages.lock \
    && truncate -s 768M /system.ext4 \
    && mkfs.ext4 -q -F -L artex-system -O ^has_journal -d /rootfs /system.ext4
