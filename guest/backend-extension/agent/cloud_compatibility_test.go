package agent

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Autumn-27/norma/llm"
)

// Loopback fixtures exercise the pinned provider's actual HTTP encoder/decoder.
// They do not establish cloud availability or Gemini tool-signature support.
func TestManagedCloudCompatibilityTextStream(t *testing.T) {
	for _, tc := range []struct{ name, prefix string }{
		{"gemini", "/v1beta/openai"}, {"groq", "/openai/v1"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var calls atomic.Int32
			key := "synthetic-" + tc.name
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				if r.Method != "POST" || r.URL.RequestURI() != tc.prefix+"/chat/completions" {
					t.Errorf("unexpected method/path: %s %s", r.Method, r.URL.RequestURI())
				}
				if r.Header.Get("Authorization") != "Bearer "+key || r.Header.Get("X-Api-Key") != "" {
					t.Error("wrong credential contract")
				}
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Error(err)
				}
				if body["model"] != "opaque-model" || body["stream"] != true {
					t.Error("wrong model/stream")
				}
				messages, ok := body["messages"].([]any)
				if !ok || len(messages) != 1 {
					t.Error("missing message")
				}
				for _, field := range []string{"thinking", "reasoning_effort", "logprobs", "logit_bias", "top_logprobs", "tools"} {
					if _, exists := body[field]; exists {
						t.Errorf("unexpected default field %s", field)
					}
				}
				w.Header().Set("Content-Type", "text/event-stream")
				_, _ = io.WriteString(w, "data: {\"id\":\"fixture\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}\n\n")
				_, _ = io.WriteString(w, "data: {\"id\":\"fixture\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
			}))
			defer upstream.Close()
			cfg := ConfigFrom("openai", "opaque-model", upstream.URL+tc.prefix+"/", key, "")
			cfg.Retry.ConnectAttempts = -1
			cfg.Retry.EmptyAttempts = -1
			provider, err := cfg.NewProvider()
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			var text string
			for event, err := range provider.Stream(ctx, llm.CompletionRequest{Messages: []llm.Message{llm.UserText("fixture")}}) {
				if err != nil {
					t.Fatal(err)
				}
				if event.Type == llm.SETextDelta {
					text += event.Text
				}
			}
			if text != "hello" || calls.Load() != 1 {
				t.Fatalf("text=%q calls=%d", text, calls.Load())
			}
		})
	}
}
