package agent

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/Autumn-27/artex/llmrec"
)

func TestManagedCloudRedirectDoesNotCrossPort(t *testing.T) {
	var transferred, credentialRequests atomic.Int32
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		transferred.Add(1)
		if r.Header.Get("Authorization") == "Bearer synthetic-completion-key" {
			credentialRequests.Add(1)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer other.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", other.URL+"/other?token=synthetic-redirect-secret")
		w.WriteHeader(http.StatusTemporaryRedirect)
		_, _ = io.WriteString(w, "synthetic-redirect-secret")
	}))
	defer origin.Close()
	client, err := quotaAwareHTTPClient("", "")
	if err != nil {
		t.Fatal(err)
	}
	ctx, capture := llmrec.NewCapture(t.Context())
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, origin.URL+"/chat/completions", strings.NewReader(`{"model":"fixture"}`))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer synthetic-completion-key")
	req.Header.Set("X-Api-Key", "synthetic-second-header")
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusTemporaryRedirect || transferred.Load() != 0 {
		t.Fatalf("completion redirect crossed origin: status=%d destination_requests=%d credential_requests=%d", resp.StatusCode, transferred.Load(), credentialRequests.Load())
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil || len(body) != 0 || strings.Contains(capture.RawResponse(), "synthetic-redirect-secret") {
		t.Fatal("completion exposed rejected redirect content")
	}
}

func TestManagedCloudRedirectOmitsMalformedLocation(t *testing.T) {
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", "/%ZZ?token=synthetic-malformed-location")
		w.WriteHeader(http.StatusTemporaryRedirect)
	}))
	defer origin.Close()
	client, err := quotaAwareHTTPClient("", "")
	if err != nil {
		t.Fatal(err)
	}
	resp, err := client.Get(origin.URL)
	if err != nil {
		t.Fatal("malformed redirect should return a status without exposing its location")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusTemporaryRedirect || resp.Header.Get("Location") != "" {
		t.Fatal("malformed redirect status or location was not sanitized")
	}
}

func TestManagedCloudRedirectAllowsRelativeSameOrigin(t *testing.T) {
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/first" {
			http.Redirect(w, r, "/second", http.StatusTemporaryRedirect)
			return
		}
		body, _ := io.ReadAll(r.Body)
		if r.URL.Path != "/second" || r.Method != http.MethodPost || string(body) != "fixture" || r.Header.Get("Authorization") != "Bearer synthetic-key" {
			t.Error("same-origin request did not preserve its contract")
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer origin.Close()
	client, err := quotaAwareHTTPClient("", "")
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, origin.URL+"/first", strings.NewReader("fixture"))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer synthetic-key")
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("same-origin status=%d", resp.StatusCode)
	}
}

func TestManagedCloudRedirectOriginAndHopBounds(t *testing.T) {
	first, err := http.NewRequest(http.MethodGet, "https://API.example.invalid/v1/models", nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		url   string
		allow bool
	}{
		{"https://api.example.invalid:443/next", true},
		{"https://api.example.invalid/next", true},
		{"http://api.example.invalid:443/next", false},
		{"https://api.example.invalid:444/next", false},
		{"https://api.example.invalid.other.invalid/next", false},
		{"https://user@api.example.invalid/next", false},
		{"https://api.example.invalid:65536/next", false},
	} {
		target, err := url.Parse(test.url)
		if err != nil {
			t.Fatal(err)
		}
		got := CheckLLMRedirect(&http.Request{URL: target}, []*http.Request{first})
		if test.allow && got != nil || !test.allow && got != http.ErrUseLastResponse {
			t.Errorf("unexpected decision for %q", test.url)
		}
	}
	redirected := &http.Request{URL: first.URL, Host: "other.invalid"}
	if CheckLLMRedirect(redirected, []*http.Request{first}) != http.ErrUseLastResponse {
		t.Error("Host override accepted")
	}
	chain := make([]*http.Request, 10)
	chain[0] = first
	if CheckLLMRedirect(first, chain) != http.ErrUseLastResponse {
		t.Error("redirect limit bypassed")
	}
	if CheckLLMRedirect(first, nil) != http.ErrUseLastResponse {
		t.Error("missing initial request accepted")
	}
}
