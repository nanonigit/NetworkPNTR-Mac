package cloudegress

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/Autumn-27/norma/llm"
)

func brokerFixture(t *testing.T, response []byte, inspect func([]byte, []byte), hold <-chan struct{}) transport {
	t.Helper()
	return transport{dial: func(_ context.Context, _ time.Time) (connection, error) {
		client, host := net.Pipe()
		exited := make(chan struct{})
		t.Cleanup(func() {
			_ = client.Close()
			_ = host.Close()
			<-exited
		})
		go func() {
			defer close(exited)
			defer host.Close()
			_ = host.SetDeadline(time.Now().Add(2 * time.Second))
			var prefix [14]byte
			if _, err := io.ReadFull(host, prefix[:]); err != nil {
				return
			}
			count := int(binary.BigEndian.Uint16(prefix[8:10])) + int(binary.BigEndian.Uint32(prefix[10:14]))
			if count > maxKey+maxBody {
				t.Error("unexpected request size")
				return
			}
			payload := make([]byte, count)
			if _, err := io.ReadFull(host, payload); err != nil {
				return
			}
			if inspect != nil {
				inspect(prefix[:], payload)
			}
			for _, b := range response {
				if _, err := host.Write([]byte{b}); err != nil {
					return
				}
			}
			if hold != nil {
				<-hold
			}
		}()
		return client, nil
	}}
}

func responseFrames(status uint16, media byte, body string, complete bool) []byte {
	wire := []byte{1, 0, 0, 0, 3, byte(status >> 8), byte(status), media}
	if body != "" {
		header := []byte{2, 0, 0, 0, 0}
		binary.BigEndian.PutUint32(header[1:], uint32(len(body)))
		wire = append(wire, header...)
		wire = append(wire, body...)
	}
	if complete {
		wire = append(wire, 3, 0, 0, 0, 0)
	}
	return wire
}

func TestManagedCloudGuestWireAndStream(t *testing.T) {
	req, err := http.NewRequest("POST", "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer fixture")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("X-Unrelated", "not-on-wire")
	wire := responseFrames(200, 2, "abc", true)
	client := brokerFixture(t, wire, func(prefix, payload []byte) {
		if !bytes.Equal(prefix, []byte{'A', 'R', 'X', 'E', 1, 7, 1, 0, 0, 7, 0, 0, 0, 2}) || !bytes.Equal(payload, []byte("fixture{}")) {
			t.Error("request bytes do not match host wire contract")
		}
	}, nil)
	result, err := client.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	defer result.Body.Close()
	got, err := io.ReadAll(result.Body)
	if err != nil || result.StatusCode != 200 || result.Header.Get("Content-Type") != "text/event-stream" || string(got) != "abc" {
		t.Fatal("stream was not decoded")
	}
}

func TestManagedCloudGuestRejectsBeforeDial(t *testing.T) {
	for _, target := range []string{
		"http://api.openai.com/v1/models", "https://api.openai.com.other.invalid/v1/models",
		"https://api.openai.com:444/v1/models", "https://api.openai.com/v1/models?",
		"https://api.openai.com/v1/%6dodels", "https://user@api.openai.com/v1/models",
		"https://api.openai.com/v1/models#fragment", "https://api.openai.com/v1/other",
	} {
		req, err := http.NewRequest("GET", target, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer fixture")
		tr := transport{dial: func(context.Context, time.Time) (connection, error) {
			t.Fatal("denied target reached broker")
			return nil, nil
		}}
		if _, err := tr.RoundTrip(req); !errors.Is(err, errTarget) {
			t.Error("denied target accepted")
		}
	}
}

func TestManagedCloudGuestMalformedResponseAndCancellation(t *testing.T) {
	for _, wire := range [][]byte{
		responseFrames(200, 1, "complete JSON before loss", false),
		append(responseFrames(200, 1, "", false), 2, 0, 0, 0, 3, 'x'),
		append(responseFrames(200, 1, "", false), 2, 0, 1, 0, 0),
		append(responseFrames(204, 1, "", false), 2, 0, 0, 0, 1, 'x'),
	} {
		req, _ := http.NewRequest("GET", "https://api.openai.com/v1/models", nil)
		req.Header.Set("Authorization", "Bearer fixture")
		response, err := brokerFixture(t, wire, nil, nil).RoundTrip(req)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.ReadAll(response.Body); err == nil {
			t.Error("missing terminal was accepted")
		}
		_ = response.Body.Close()
	}
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	release := make(chan struct{})
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://api.openai.com/v1/models", nil)
	req.Header.Set("Authorization", "Bearer fixture")
	tr := brokerFixture(t, responseFrames(200, 1, "", false), nil, release)
	defer close(release)
	response, err := tr.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	done := make(chan error, 1)
	go func() { _, err := io.ReadAll(response.Body); done <- err }()
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("cancellation error=%v", err)
		}
	case <-time.After(time.Second):
		t.Error("cancellation did not interrupt read")
	}
}

func TestManagedCloudGuestOpenAISDKRequiresBrokerEndAfterDone(t *testing.T) {
	const sse = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"fixture\"}}]}\n\ndata: [DONE]\n\n"
	for _, complete := range []bool{false, true} {
		tr := brokerFixture(t, responseFrames(200, 2, sse, complete), nil, nil)
		provider, err := llm.NewProvider(llm.Config{Format: llm.FormatOpenAI, APIKey: "fixture",
			Model: "fixture", MaxRetries: -1, HTTPClient: &http.Client{Transport: tr}})
		if err != nil {
			t.Fatal(err)
		}
		var failure error
		for _, err := range provider.Stream(t.Context(), llm.CompletionRequest{}) {
			if err != nil {
				failure = err
			}
		}
		if complete && failure != nil {
			t.Errorf("completed broker stream failed: %v", failure)
		}
		if !complete && !errors.Is(failure, io.ErrUnexpectedEOF) {
			t.Error("SDK accepted DONE without broker terminal")
		}
	}
}

func TestManagedCloudGuestExplicitModes(t *testing.T) {
	base := http.DefaultTransport
	t.Setenv("ARTEX_MAC_CLOUD_EGRESS", "")
	if ProviderTransport(base, true) != base {
		t.Fatal("disabled mode did not preserve transport")
	}
	t.Setenv("ARTEX_MAC_CLOUD_EGRESS", "vsock-v1")
	if _, ok := ProviderTransport(base, false).(transport); !ok {
		t.Fatal("vsock mode did not choose broker")
	}
	if _, ok := ProviderTransport(base, true).(deniedTransport); !ok {
		t.Fatal("custom routing not denied")
	}
	t.Setenv("ARTEX_MAC_CLOUD_EGRESS", "typo")
	if _, ok := ProviderTransport(base, false).(deniedTransport); !ok {
		t.Fatal("unknown mode not denied")
	}
}

func TestManagedCloudGuestDoesNotReplayUnconfirmedPOST(t *testing.T) {
	for name, wire := range map[string][]byte{
		"missing head":    nil,
		"malformed head":  responseFrames(307, 0, "", true),
		"429 without end": responseFrames(429, 1, "quota", false),
		"503 without end": responseFrames(503, 1, "unavailable", false),
		"401 without end": responseFrames(401, 1, "unauthorized", false),
	} {
		t.Run(name, func(t *testing.T) {
			tr := brokerFixture(t, wire, nil, nil)
			dial := tr.dial
			calls := 0
			tr.dial = func(ctx context.Context, deadline time.Time) (connection, error) {
				calls++
				return dial(ctx, deadline)
			}
			provider, err := llm.NewProvider(llm.Config{Format: llm.FormatOpenAI, APIKey: "fixture",
				Model: "fixture", RetryInterval: time.Millisecond, HTTPClient: &http.Client{Transport: tr}})
			if err != nil {
				t.Fatal(err)
			}
			var failure error
			for _, err := range provider.Stream(t.Context(), llm.CompletionRequest{}) {
				if err != nil {
					failure = err
				}
			}
			want := io.ErrUnexpectedEOF
			if name == "malformed head" {
				want = errProtocol
			}
			if calls != 1 || !errors.Is(failure, want) {
				t.Errorf("unconfirmed request calls=%d failure=%v", calls, failure)
			}
		})
	}
}

func TestManagedCloudGuestSSEProviderErrorNeedsBrokerTerminal(t *testing.T) {
	const stream = "event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"insufficient_quota\"}}\n\n"
	for _, format := range []llm.Format{llm.FormatAnthropic, llm.FormatOpenAIResponses} {
		t.Run(string(format), func(t *testing.T) {
			for _, complete := range []bool{false, true} {
				tr := brokerFixture(t, responseFrames(200, 2, stream, complete), nil, nil)
				provider, err := llm.NewProvider(llm.Config{Format: format, APIKey: "fixture",
					Model: "fixture", MaxRetries: -1, HTTPClient: &http.Client{Transport: tr}})
				if err != nil {
					t.Fatal(err)
				}
				var failure error
				for _, err := range provider.Stream(t.Context(), llm.CompletionRequest{}) {
					if err != nil {
						failure = err
					}
				}
				if complete {
					if failure == nil || !strings.Contains(failure.Error(), "insufficient_quota") || ReplayUnsafe(failure) {
						t.Errorf("confirmed provider error lost: %v", failure)
					}
				} else if !errors.Is(failure, io.ErrUnexpectedEOF) || !ReplayUnsafe(failure) {
					t.Errorf("truncated provider error was not classified as unknown: %v", failure)
				}
			}
		})
	}
}
