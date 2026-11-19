FROM golang:1.26.3-bookworm@sha256:386d475a660466863d9f8c766fec64d7fdad3edac2c6a05020c09534d71edb4b AS compiler
COPY check.c test.c /tmp/
RUN --network=none gcc -static -O2 -std=c11 -Wall -Wextra -Werror -o /tmp/check-blank-disk /tmp/check.c
RUN --network=none gcc -static -O2 -std=c11 -Wall -Wextra -Werror -o /tmp/test /tmp/test.c -Wl,--wrap=fstat,--wrap=ioctl,--wrap=read \
    && /tmp/test
FROM networkpntr-preserved-runtime:31c282753a7714f56fc3c0d98a76f69e1281f519f7edc6fbd137676a72441e3d
COPY --from=compiler /tmp/check-blank-disk /rootfs/opt/artex-mac/check-blank-disk
RUN --network=none test "$(grep -Fc 'python3 /opt/artex-mac/check_blank_disk.py || blank_status=$?' /rootfs/sbin/artex-init)" -eq 1 \
    && sed -i 's@python3 /opt/artex-mac/check_blank_disk.py || blank_status=$?@/opt/artex-mac/check-blank-disk || blank_status=$?@' /rootfs/sbin/artex-init \
    && unlink /system.ext4 && truncate -s 768M /system.ext4 \
    && mkfs.ext4 -q -F -L artex-system -O ^has_journal -d /rootfs /system.ext4
