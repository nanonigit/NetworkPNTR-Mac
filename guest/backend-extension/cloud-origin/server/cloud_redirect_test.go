package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func TestManagedCloudRedirectModelDiscoveryDoesNotCrossPort(t *testing.T) {
	var transferred, credentialRequests atomic.Int32
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		transferred.Add(1)
		if r.Header.Get("Authorization") == "Bearer synthetic-discovery-key" {
			credentialRequests.Add(1)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"data": []any{map[string]string{"id": "unexpected-model"}}})
	}))
	defer other.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, other.URL+"/other", http.StatusTemporaryRedirect)
	}))
	defer origin.Close()
	body, err := json.Marshal(map[string]string{"provider": "openai", "base_url": origin.URL + "/v1beta/openai/", "api_key": "synthetic-discovery-key"})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/llm/models", bytes.NewReader(body))
	response := httptest.NewRecorder()
	(&Server{}).pgListModels(response, request)
	var result struct {
		OK bool `json:"ok"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.OK || transferred.Load() != 0 {
		t.Fatalf("discovery redirect crossed origin: ok=%v destination_requests=%d credential_requests=%d", result.OK, transferred.Load(), credentialRequests.Load())
	}
}
