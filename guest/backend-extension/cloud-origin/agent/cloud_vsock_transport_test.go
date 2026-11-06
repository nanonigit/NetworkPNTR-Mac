package agent

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/Autumn-27/artex/cloudegress"
	"github.com/Autumn-27/artex/llmrec"
)

func TestManagedCloudGuestCompletionCannotFallBackToDirect(t *testing.T) {
	t.Setenv("ARTEX_MAC_CLOUD_EGRESS", "vsock-v1")
	var requests atomic.Int32
	local := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer local.Close()
	client, err := quotaAwareHTTPClient("", "")
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, local.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer fixture")
	if resp, err := client.Do(req); err == nil {
		resp.Body.Close()
		t.Error("blocked completion used a direct destination")
	}
	if requests.Load() != 0 {
		t.Error("unexpected direct request")
	}
}

func TestManagedCloudGuestRejectsCustomCompletionRouting(t *testing.T) {
	t.Setenv("ARTEX_MAC_CLOUD_EGRESS", "vsock-v1")
	client, err := quotaAwareHTTPClient("://fixture-secret", "")
	if err != nil {
		t.Fatal("proxy should be rejected by the broker policy before parsing")
	}
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, "https://api.openai.com/v1/models", nil)
	if err != nil {
		t.Fatal(err)
	}
	if resp, err := client.Do(req); err == nil {
		resp.Body.Close()
		t.Error("custom proxy accepted")
	} else if strings.Contains(err.Error(), "fixture-secret") {
		t.Error("proxy credentials exposed")
	}
}

type cloudGuestFramedBody struct{ io.ReadCloser }

func (cloudGuestFramedBody) RequiresTransportEnd() bool { return true }

type cloudGuestTruncatedReader struct{}

func (cloudGuestTruncatedReader) Read([]byte) (int, error) { return 0, io.ErrUnexpectedEOF }

type cloudGuestErrorStatusTransport struct{ status int }

func (t cloudGuestErrorStatusTransport) RoundTrip(*http.Request) (*http.Response, error) {
	body := io.MultiReader(strings.NewReader("incomplete status"), cloudGuestTruncatedReader{})
	return &http.Response{StatusCode: t.status, Body: cloudGuestFramedBody{io.NopCloser(body)}}, nil
}

func TestManagedCloudGuestCapturePreservesTerminalAndRejectsTruncatedQuota(t *testing.T) {
	ctx, _ := llmrec.NewCapture(t.Context())
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.openai.com/v1/models", nil)
	if err != nil {
		t.Fatal(err)
	}
	tr := quotaAwareTransport{base: cloudGuestErrorStatusTransport{http.StatusServiceUnavailable}}
	resp, err := tr.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	if !cloudegress.RequiresTransportEnd(resp.Body) {
		t.Error("capture lost terminal requirement")
	}
	_ = resp.Body.Close()

	tr.base = cloudGuestErrorStatusTransport{http.StatusTooManyRequests}
	resp, err = tr.RoundTrip(req)
	if resp != nil || !errors.Is(err, io.ErrUnexpectedEOF) || !cloudegress.ReplayUnsafe(err) {
		t.Fatal("capture accepted or enabled retry of truncated quota response")
	}
}
