package cloudegress

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	maxKey   = 4096
	maxBody  = 16 * 1024 * 1024
	maxChunk = 16 * 1024
)

var (
	errTarget   = errors.New("cloud egress target is not permitted")
	errConfig   = errors.New("cloud egress configuration is not supported")
	errProtocol = errors.New("invalid cloud egress response")
)

type requestTarget struct {
	host, method, path string
}

var routes = map[requestTarget]byte{
	{"api.openai.com", "GET", "/v1/models"}:                                          1,
	{"api.openai.com", "POST", "/v1/chat/completions"}:                               2,
	{"api.openai.com", "POST", "/v1/responses"}:                                      3,
	{"api.anthropic.com", "GET", "/v1/models"}:                                       4,
	{"api.anthropic.com", "POST", "/v1/messages"}:                                    5,
	{"generativelanguage.googleapis.com", "GET", "/v1beta/openai/models"}:            6,
	{"generativelanguage.googleapis.com", "POST", "/v1beta/openai/chat/completions"}: 7,
	{"api.groq.com", "GET", "/openai/v1/models"}:                                     8,
	{"api.groq.com", "POST", "/openai/v1/chat/completions"}:                          9,
}

type connection interface {
	io.ReadWriteCloser
	SetDeadline(time.Time) error
}

type transport struct {
	dial func(context.Context, time.Time) (connection, error)
}

type deniedTransport struct{}

func (deniedTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if req.Body != nil {
		_ = req.Body.Close()
	}
	return nil, errConfig
}

// ProviderTransport chooses the managed transport before any request is sent.
func ProviderTransport(direct http.RoundTripper, customRouting bool) http.RoundTripper {
	switch os.Getenv("ARTEX_MAC_CLOUD_EGRESS") {
	case "":
		return direct
	case "vsock-v1":
		if !customRouting {
			return transport{dial: dialHost}
		}
	}
	return deniedTransport{}
}

func requestParts(req *http.Request) ([]byte, string, []byte, error) {
	u := req.URL
	if u == nil || u.Scheme != "https" || u.User != nil || u.RawPath != "" || u.RawQuery != "" ||
		u.ForceQuery || u.Fragment != "" || u.RawFragment != "" || u.Opaque != "" ||
		(req.Host != "" && req.Host != u.Host) {
		return nil, "", nil, errTarget
	}
	host := strings.TrimSuffix(u.Host, ":443")
	route := routes[requestTarget{host, req.Method, u.Path}]
	if route == 0 {
		return nil, "", nil, errTarget
	}
	var key string
	if route == 4 || route == 5 {
		if len(req.Header.Values("X-Api-Key")) == 1 && len(req.Header.Values("Authorization")) == 0 {
			key = req.Header.Get("X-Api-Key")
		}
	} else if len(req.Header.Values("Authorization")) == 1 && len(req.Header.Values("X-Api-Key")) == 0 {
		key, _ = strings.CutPrefix(req.Header.Get("Authorization"), "Bearer ")
	}
	if key == "" || len(key) > maxKey {
		return nil, "", nil, errTarget
	}
	for i := range len(key) {
		if key[i] < 0x21 || key[i] > 0x7e {
			return nil, "", nil, errTarget
		}
	}

	streaming := req.Header.Get("Accept") == "text/event-stream"
	encoding := req.Header.Get("Content-Encoding")
	if req.ContentLength > maxBody || (encoding != "" && encoding != "identity") ||
		(req.Method == "GET" && (streaming || req.ContentLength != 0 || (req.Body != nil && req.Body != http.NoBody))) {
		return nil, "", nil, errTarget
	}
	var body []byte
	if req.Method == "POST" {
		if req.Body == nil {
			return nil, "", nil, errTarget
		}
		var err error
		body, err = io.ReadAll(io.LimitReader(req.Body, maxBody+1))
		if err != nil || len(body) == 0 || len(body) > maxBody ||
			(req.ContentLength > 0 && req.ContentLength != int64(len(body))) {
			return nil, "", nil, errTarget
		}
	}
	prefix := []byte{'A', 'R', 'X', 'E', 1, route, 0, 0, 0, 0, 0, 0, 0, 0}
	if streaming {
		prefix[6] = 1
	}
	binary.BigEndian.PutUint16(prefix[8:10], uint16(len(key)))
	binary.BigEndian.PutUint32(prefix[10:], uint32(len(body)))
	return prefix, key, body, nil
}

func (t transport) RoundTrip(req *http.Request) (*http.Response, error) {
	if req.Body != nil {
		defer req.Body.Close()
	}
	ctx := req.Context()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	prefix, key, body, err := requestParts(req)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(120 * time.Second)
	if limit, ok := ctx.Deadline(); ok && limit.Before(deadline) {
		deadline = limit
	}
	conn, err := t.dial(ctx, deadline)
	if err != nil {
		return nil, err
	}
	stop := context.AfterFunc(ctx, func() { _ = conn.Close() })
	stream := &responseBody{conn: conn, ctx: ctx, stop: stop}
	keep := false
	defer func() {
		if !keep {
			_ = stream.Close()
		}
	}()
	if err := conn.SetDeadline(deadline); err != nil {
		return nil, err
	}
	for _, part := range [][]byte{prefix, []byte(key), body} {
		if len(part) == 0 {
			continue
		}
		if count, err := conn.Write(part); err != nil || count != len(part) {
			return nil, NoReplay(stream.transportError())
		}
	}
	var head [8]byte
	if _, err := io.ReadFull(conn, head[:]); err != nil {
		return nil, NoReplay(stream.transportError())
	}
	status := int(binary.BigEndian.Uint16(head[5:7]))
	if head[0] != 1 || binary.BigEndian.Uint32(head[1:5]) != 3 ||
		status < 200 || status > 599 || (status >= 300 && status < 400) || head[7] > 2 {
		return nil, NoReplay(errProtocol)
	}
	headers := make(http.Header)
	switch head[7] {
	case 1:
		headers.Set("Content-Type", "application/json")
	case 2:
		headers.Set("Content-Type", "text/event-stream")
	}
	stream.bodyless = status == 204 || status == 205
	keep = true
	return &http.Response{
		StatusCode: status, Status: fmt.Sprintf("%d %s", status, http.StatusText(status)),
		Header: headers, Body: stream, ContentLength: -1, Close: true,
		Request: req, Proto: "HTTP/1.1", ProtoMajor: 1, ProtoMinor: 1,
	}, nil
}

type responseBody struct {
	conn      connection
	ctx       context.Context
	stop      func() bool
	remaining int
	total     int
	bodyless  bool
	terminal  error
}

func (b *responseBody) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	if b.terminal != nil {
		return 0, b.terminal
	}
	if b.remaining == 0 {
		var frame [5]byte
		if _, err := io.ReadFull(b.conn, frame[:]); err != nil {
			return b.finish(0, NoReplay(b.transportError()))
		}
		length := int(binary.BigEndian.Uint32(frame[1:]))
		if frame[0] == 3 && length == 0 {
			return b.finish(0, io.EOF)
		}
		if frame[0] != 2 || length <= 0 || length > maxChunk || length > maxBody-b.total || b.bodyless {
			return b.finish(0, NoReplay(errProtocol))
		}
		b.remaining = length
		b.total += length
	}
	count, err := io.ReadFull(b.conn, p[:min(len(p), b.remaining)])
	b.remaining -= count
	if err != nil {
		return b.finish(count, NoReplay(b.transportError()))
	}
	return count, nil
}

func (b *responseBody) transportError() error {
	if err := b.ctx.Err(); err != nil {
		return err
	}
	return io.ErrUnexpectedEOF
}

func (b *responseBody) finish(count int, err error) (int, error) {
	b.terminal = err
	_ = b.Close()
	return count, err
}

func (b *responseBody) Close() error {
	b.stop()
	_ = b.conn.Close()
	return nil
}

func (*responseBody) RequiresTransportEnd() bool { return true }

// PreserveTransportEnd keeps the broker completion marker across recording.
func PreserveTransportEnd(original, wrapped io.ReadCloser) io.ReadCloser {
	if RequiresTransportEnd(original) {
		return framedReadCloser{wrapped}
	}
	return wrapped
}

func RequiresTransportEnd(body io.ReadCloser) bool {
	terminal, ok := body.(interface{ RequiresTransportEnd() bool })
	return ok && terminal.RequiresTransportEnd()
}

type framedReadCloser struct{ io.ReadCloser }

func (framedReadCloser) RequiresTransportEnd() bool { return true }

// NoReplay marks a failed exchange after bytes might have reached the host.
// The SDK must not establish another POST when its outcome is unknown.
func NoReplay(err error) error { return uncertainResponse{err} }

type uncertainResponse struct{ error }

func (e uncertainResponse) Unwrap() error       { return e.error }
func (uncertainResponse) NoProviderRetry() bool { return true }

// ReplayUnsafe reports an unconfirmed provider exchange through wrapped errors.
func ReplayUnsafe(err error) bool {
	var marker interface{ NoProviderRetry() bool }
	return errors.As(err, &marker) && marker.NoProviderRetry()
}
