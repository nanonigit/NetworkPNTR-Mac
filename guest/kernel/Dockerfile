FROM alpine:3.22.7@sha256:e9f2de928efcc1b53d0948e684b4f490315f280de6044844ec0ff26c0b44d3cf
RUN apk add --no-cache build-base=0.5-r3 bc=1.08.2-r0 bison=3.8.2-r2 flex=2.6.4-r7 perl=5.40.4-r0 openssl-dev=3.5.9-r0 elfutils-dev=0.193-r0 python3=3.12.15-r0 xz=5.8.4-r0
RUN apk add --no-cache gmp-dev=6.3.0-r3
RUN apk add --no-cache mpc1-dev=1.3.1-r1 mpfr-dev=4.2.1_p1-r0
COPY builder-packages.lock /expected-packages.lock
RUN apk info -vv > /actual-packages.lock && cmp -s /actual-packages.lock /expected-packages.lock
COPY linux-source.tar.xz base.config config-LICENSE config-overrides source.lock.json /inputs/
COPY prepare_kernel.py /tools/prepare_kernel.py
COPY build-kernel.sh /tools/build-kernel.sh
ENTRYPOINT ["/bin/sh", "/tools/build-kernel.sh"]
