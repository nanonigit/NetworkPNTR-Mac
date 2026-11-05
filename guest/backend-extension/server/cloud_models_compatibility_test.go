package server

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

// This uses the real model-list handler with supplied synthetic keys and no DB.
func TestManagedCloudCompatibilityModelDiscovery(t *testing.T) {
	for _, tc := range []struct{ name, prefix string }{
		{"gemini", "/v1beta/openai"}, {"groq", "/openai/v1"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var calls atomic.Int32
			key := "synthetic-" + tc.name
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				if r.Method != "GET" || r.URL.RequestURI() != tc.prefix+"/models" {
					t.Error("wrong model-list route")
				}
				if r.Header.Get("Authorization") != "Bearer "+key || r.Header.Get("X-Api-Key") != "" {
					t.Error("wrong credential contract")
				}
				w.Header().Set("Content-Type", "application/json")
				_, _ = io.WriteString(w, `{"data":[{"id":"opaque-model"}]}`)
			}))
			defer upstream.Close()
			body, err := json.Marshal(map[string]any{"provider": "openai", "base_url": upstream.URL + tc.prefix + "/", "api_key": key})
			if err != nil {
				t.Fatal(err)
			}
			request := httptest.NewRequest("POST", "/api/llm/models", bytes.NewReader(body))
			response := httptest.NewRecorder()
			(&Server{}).pgListModels(response, request)
			var result struct {
				OK     bool     `json:"ok"`
				Models []string `json:"models"`
			}
			if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
				t.Fatal(err)
			}
			if response.Code != 200 || !result.OK || len(result.Models) != 1 || result.Models[0] != "opaque-model" || calls.Load() != 1 {
				t.Fatalf("status=%d ok=%v models=%v calls=%d", response.Code, result.OK, result.Models, calls.Load())
			}
		})
	}
}
