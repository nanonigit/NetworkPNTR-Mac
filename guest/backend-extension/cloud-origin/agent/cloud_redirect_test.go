package agent

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
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
		http.Redirect(w, r, other.URL+"/other", http.StatusTemporaryRedirect)
	}))
	defer origin.Close()
	client, err := quotaAwareHTTPClient("", "")
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, origin.URL+"/chat/completions", strings.NewReader(`{"model":"fixture"}`))
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
