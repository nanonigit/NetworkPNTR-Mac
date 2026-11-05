package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Autumn-27/norma/llm"
)

// A synthetic model requests harmless fixture results; no tool is executed.
func TestManagedCloudCompatibilityToolHistory(t *testing.T) {
	for _, signature := range []bool{false, true} {
		for _, streaming := range []bool{false, true} {
			t.Run(fmt.Sprintf("signature=%v/stream=%v", signature, streaming), func(t *testing.T) {
				signatures := []string{"opaque+/first==", "opaque+/second=="}
				inputs := []string{`{"value":"first"}`, `{"value":"second"}`}
				var calls atomic.Int32
				frame := func(w http.ResponseWriter, delta map[string]any, finish any) {
					raw, _ := json.Marshal(map[string]any{"choices": []any{map[string]any{"index": 0, "delta": delta, "finish_reason": finish}}})
					data := []byte("data: " + string(raw) + "\n\n")
					for len(data) > 0 {
						n := min(7, len(data))
						_, _ = w.Write(data[:n])
						data = data[n:]
						w.(http.Flusher).Flush()
					}
				}
				upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					round := calls.Add(1)
					var body map[string]any
					if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
						t.Error(err)
						return
					}
					if round == 2 {
						messages, ok := body["messages"].([]any)
						if !ok || len(messages) != 4 {
							t.Error("expected user, assistant and two tool results")
							w.WriteHeader(400)
							return
						}
						assistant := messages[1].(map[string]any)
						tools, ok := assistant["tool_calls"].([]any)
						if !ok || len(tools) != 2 {
							t.Error("missing assistant tool history")
							w.WriteHeader(400)
							return
						}
						for i, raw := range tools {
							tool := raw.(map[string]any)
							if tool["id"] != fmt.Sprintf("call-%d", i) {
								t.Error("tool identity changed")
							}
							fn := tool["function"].(map[string]any)
							var gotInput, wantInput any
							_ = json.Unmarshal([]byte(fn["arguments"].(string)), &gotInput)
							_ = json.Unmarshal([]byte(inputs[i]), &wantInput)
							if !reflect.DeepEqual(gotInput, wantInput) {
								t.Errorf("tool %d arguments changed", i)
							}
							if signature {
								extra, _ := tool["extra_content"].(map[string]any)
								google, _ := extra["google"].(map[string]any)
								if google["thought_signature"] != signatures[i] {
									t.Errorf("tool %d lost signature on replay", i)
								}
							} else if _, exists := tool["extra_content"]; exists {
								t.Error("unsigned tool acquired vendor metadata")
							}
							result := messages[i+2].(map[string]any)
							if result["role"] != "tool" || result["tool_call_id"] != fmt.Sprintf("call-%d", i) || result["content"] != "fixture-result" {
								t.Error("tool result association changed")
							}
						}
						if streaming {
							w.Header().Set("Content-Type", "text/event-stream")
							frame(w, map[string]any{"content": "done"}, "stop")
							_, _ = io.WriteString(w, "data: [DONE]\n\n")
						} else {
							w.Header().Set("Content-Type", "application/json")
							_, _ = io.WriteString(w, `{"choices":[{"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}]}`)
						}
						return
					}
					if round != 1 {
						t.Error("unexpected replay/retry")
						w.WriteHeader(500)
						return
					}
					if streaming {
						w.Header().Set("Content-Type", "text/event-stream")
						for i := 0; i < 2; i++ {
							frame(w, map[string]any{"tool_calls": []any{map[string]any{"index": i, "id": fmt.Sprintf("call-%d", i), "type": "function", "function": map[string]any{"name": "fixture", "arguments": ""}}}}, nil)
						}
						// Interleave inputs and deliver signatures after both starts.
						for i := 0; i < 2; i++ {
							tc := map[string]any{"index": i, "function": map[string]any{"arguments": inputs[i]}}
							if signature {
								tc["extra_content"] = map[string]any{"google": map[string]any{"thought_signature": signatures[i]}}
							}
							frame(w, map[string]any{"tool_calls": []any{tc}}, nil)
						}
						frame(w, map[string]any{}, "tool_calls")
						_, _ = io.WriteString(w, "data: [DONE]\n\n")
					} else {
						tools := []any{}
						for i := 0; i < 2; i++ {
							tc := map[string]any{"id": fmt.Sprintf("call-%d", i), "type": "function", "function": map[string]any{"name": "fixture", "arguments": inputs[i]}}
							if signature {
								tc["extra_content"] = map[string]any{"google": map[string]any{"thought_signature": signatures[i]}}
							}
							tools = append(tools, tc)
						}
						_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"role": "assistant", "tool_calls": tools}, "finish_reason": "tool_calls"}}})
					}
				}))
				defer upstream.Close()
				cfg := ConfigFrom("openai", "opaque-model", upstream.URL+"/v1beta/openai", "synthetic-only", "")
				cfg.Retry.ConnectAttempts = -1
				cfg.Retry.EmptyAttempts = -1
				provider, err := cfg.NewProvider()
				if err != nil {
					t.Fatal(err)
				}
				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer cancel()
				request := llm.CompletionRequest{Messages: []llm.Message{llm.UserText("fixture")}}
				consume := func() llm.Message {
					if !streaming {
						msg, _, _, err := provider.Complete(ctx, request)
						if err != nil {
							t.Fatal(err)
						}
						return msg
					}
					accumulator := llm.NewAccumulator()
					for event, err := range provider.Stream(ctx, request) {
						if err != nil {
							t.Fatal(err)
						}
						accumulator.Add(event)
					}
					return accumulator.Message()
				}
				first := consume()
				// Exercise the actual normalized JSON history boundary, not a side cache.
				saved, err := json.Marshal(first)
				if err != nil {
					t.Fatal(err)
				}
				var restored llm.Message
				if err := json.Unmarshal(saved, &restored); err != nil {
					t.Fatal(err)
				}
				request.Messages = append(request.Messages, restored, llm.Message{Role: llm.RoleUser, Content: []llm.ContentBlock{llm.ToolResultText("call-0", "fixture-result", false), llm.ToolResultText("call-1", "fixture-result", false)}})
				final := consume()
				if final.Text() != "done" || calls.Load() != 2 {
					t.Fatalf("final=%q calls=%d", final.Text(), calls.Load())
				}
			})
		}
	}
}
