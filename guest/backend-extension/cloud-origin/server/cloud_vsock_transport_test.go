package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/Autumn-27/artex/cloudegress"
	"github.com/Autumn-27/norma/harness"
)

func TestManagedCloudGuestDiscoveryRejectsPartialAndNoFallback(t *testing.T) {
	var requests atomic.Int32
	local := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.Header().Set("Content-Length", "200")
		fmt.Fprint(w, `{"data":[{"id":"fixture"}]}`)
	}))
	defer local.Close()
	for _, mode := range []string{"", "vsock-v1"} {
		t.Setenv("ARTEX_MAC_CLOUD_EGRESS", mode)
		body := fmt.Sprintf(`{"provider":"openai","base_url":%q,"api_key":"fixture"}`, local.URL)
		rec := httptest.NewRecorder()
		(&Server{}).pgListModels(rec, httptest.NewRequest(http.MethodPost, "/api/llm/models", strings.NewReader(body)))
		var result struct{ OK bool }
		if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil || result.OK {
			t.Errorf("mode %q accepted truncated or disallowed discovery", mode)
		}
	}
	if requests.Load() != 1 {
		t.Errorf("direct requests=%d; expected only the disabled-mode fixture", requests.Load())
	}
}

func TestManagedCloudGuestTaskAndWorkerDoNotRetryUnconfirmedExchange(t *testing.T) {
	err := fmt.Errorf("wrapped: %w", cloudegress.NoReplay(fmt.Errorf("unexpected EOF")))
	if isRetryableStreamError(err) || retryableWorkerModelError(harness.ReasonModelError, err) {
		t.Fatal("task or worker would replay an unconfirmed provider exchange")
	}
}
