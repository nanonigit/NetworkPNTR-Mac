FROM golang:1.26.3-bookworm@sha256:386d475a660466863d9f8c766fec64d7fdad3edac2c6a05020c09534d71edb4b
WORKDIR /src
ENV GOTOOLCHAIN=local CGO_ENABLED=0
COPY source/go.mod source/go.sum ./
RUN go mod download && go mod verify
COPY source/ ./
COPY server/ ./server/
COPY managed.patch /tmp/native.patch
RUN git apply --check /tmp/native.patch && git apply /tmp/native.patch
RUN --network=none GOMAXPROCS=2 go test -p 2 -mod=readonly ./server -run Native -count=1
RUN --network=none GOMAXPROCS=2 go test -p 2 -mod=readonly ./server -count=1
RUN --network=none GOMAXPROCS=2 go build -p 2 -mod=readonly -trimpath -buildvcs=false -ldflags="-s -w" -o /out/backend ./cmd/artex
