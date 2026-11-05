package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Autumn-27/artex/db"
	"github.com/Autumn-27/norma/transcript"
)

const (
	cloudTranscriptSession     = "conv-987653"
	cloudTranscriptModel       = "fixture-transcript-model"
	cloudTranscriptKey         = "synthetic-transcript-key"
	cloudTranscriptSignature   = "opaque+/transcript-signature=="
	cloudTranscriptCall        = "call-read-witness"
	cloudTranscriptMarker      = "controlled-local-tool-result"
	cloudTranscriptFirst       = "Read the local transcript fixture"
	cloudTranscriptResume      = "Continue the saved transcript fixture"
	cloudTranscriptFirstReply  = "fixture tool result accepted"
	cloudTranscriptResumeReply = "fixture saved history accepted"
)

type cloudTranscriptTool struct {
	ID       string `json:"id"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
	Extra struct {
		Google struct {
			Signature string `json:"thought_signature"`
		} `json:"google"`
	} `json:"extra_content"`
}

type cloudTranscriptRequest struct {
	Model    string `json:"model"`
	Stream   bool   `json:"stream"`
	Messages []struct {
		Role       string                `json:"role"`
		Content    string                `json:"content"`
		ToolCallID string                `json:"tool_call_id"`
		ToolCalls  []cloudTranscriptTool `json:"tool_calls"`
	} `json:"messages"`
}

// Exercise the real ChatAgent and transcript store across separate Linux processes.
// The mock upstream can request one Read of an owned fixture file.
func TestManagedCloudCompatibilityChatTranscript(t *testing.T) {
	if phase := os.Getenv("ARTEX_TEST_CLOUD_TRANSCRIPT_PHASE"); phase != "" {
		runCloudTranscriptChild(t, phase)
		return
	}
	for _, stream := range []bool{false, true} {
		t.Run(fmt.Sprintf("stream=%v", stream), func(t *testing.T) {
			dir := t.TempDir()
			witness := filepath.Join(dir, "read-witness.txt")
			if err := os.WriteFile(witness, []byte(cloudTranscriptMarker+"\n"), 0600); err != nil {
				t.Fatal(err)
			}
			var requests atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				round := requests.Add(1)
				var request cloudTranscriptRequest
				if r.Method != http.MethodPost || r.URL.RequestURI() != "/v1beta/openai/chat/completions" || r.Header.Get("Authorization") != "Bearer "+cloudTranscriptKey ||
					json.NewDecoder(io.LimitReader(r.Body, 2<<20)).Decode(&request) != nil || request.Model != cloudTranscriptModel || request.Stream != stream {
					t.Error("unexpected transcript provider request")
					http.Error(w, "fixture request rejected", http.StatusBadRequest)
					return
				}
				if err := verifyCloudTranscriptRequest(request, round, witness); err != nil {
					t.Error(err)
					http.Error(w, "fixture history rejected", http.StatusBadRequest)
					return
				}
				writeCloudTranscriptResponse(w, stream, round, witness)
			}))
			defer server.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 40*time.Second)
			defer cancel()
			run := func(phase string) {
				cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestManagedCloudCompatibilityChatTranscript$", "-test.count=1", "-test.v")
				cmd.Env = []string{
					"HOME=" + dir, "TMPDIR=" + dir, "GOMAXPROCS=2",
					"ARTEX_TEST_CLOUD_TRANSCRIPT_PHASE=" + phase,
					"ARTEX_TEST_CLOUD_TRANSCRIPT_DIR=" + dir,
					"ARTEX_TEST_CLOUD_TRANSCRIPT_BASE=" + server.URL + "/v1beta/openai/",
					fmt.Sprintf("ARTEX_TEST_CLOUD_TRANSCRIPT_STREAM=%v", stream),
				}
				if output, err := cmd.CombinedOutput(); err != nil {
					t.Fatalf("%s child: %v\n%s", phase, err, output)
				}
			}
			run("first")
			if requests.Load() != 2 {
				t.Fatalf("first turn requests=%d", requests.Load())
			}
			store := transcript.NewStore(filepath.Join(dir, "transcripts"))
			saved, err := os.ReadFile(store.MainPath(cloudTranscriptSession))
			if err != nil {
				t.Fatal(err)
			}
			for _, marker := range []string{cloudTranscriptSignature, "openai_thought_signature_scope", cloudTranscriptMarker, cloudTranscriptFirstReply} {
				if !bytes.Contains(saved, []byte(marker)) {
					t.Errorf("missing persisted witness %q", marker)
				}
			}
			if err := os.Remove(witness); err != nil {
				t.Fatal(err)
			}
			run("resume")
			if requests.Load() != 3 {
				t.Fatalf("resumed turn requests=%d", requests.Load())
			}
			after, err := os.ReadFile(store.MainPath(cloudTranscriptSession))
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.HasPrefix(after, saved) || !bytes.Contains(after[len(saved):], []byte(cloudTranscriptResumeReply)) {
				t.Fatal("restored turn did not append to the original transcript")
			}
		})
	}
}

func runCloudTranscriptChild(t *testing.T, phase string) {
	dir := os.Getenv("ARTEX_TEST_CLOUD_TRANSCRIPT_DIR")
	base := os.Getenv("ARTEX_TEST_CLOUD_TRANSCRIPT_BASE")
	stream := os.Getenv("ARTEX_TEST_CLOUD_TRANSCRIPT_STREAM") == "true"
	if !filepath.IsAbs(dir) || !validCloudTranscriptEndpoint(base) {
		t.Fatal("missing local fixture inputs")
	}
	message, expected, expectedTools := cloudTranscriptFirst, cloudTranscriptFirstReply, 1
	switch phase {
	case "first":
	case "resume":
		message, expected, expectedTools = cloudTranscriptResume, cloudTranscriptResumeReply, 0
	default:
		t.Fatal("unexpected child phase")
	}
	cfg := ConfigFrom("openai", cloudTranscriptModel, base, cloudTranscriptKey, "")
	cfg.Retry.ConnectAttempts = -1
	cfg.Retry.EmptyAttempts = -1
	provider, err := cfg.NewProvider()
	if err != nil {
		t.Fatal(err)
	}
	store := transcript.NewStore(filepath.Join(dir, "transcripts"))
	chat := NewChatAgent(provider, cloudTranscriptModel, dir, store, 100000)
	chat.SetNonStreaming(func() bool { return !stream })
	toolUses := 0
	reply, err := chat.Chat(t.Context(), "mainagent", cloudTranscriptSession, message, 4, 15*time.Second, false, func(activity db.Activity) {
		if activity.Kind == "tool_use" {
			toolUses++
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	if reply != expected || toolUses != expectedTools {
		t.Fatalf("unexpected turn outcome: tools=%d", toolUses)
	}
}

func verifyCloudTranscriptRequest(request cloudTranscriptRequest, round int32, witness string) error {
	var users []string
	var toolIndex, resultIndex = -1, -1
	for index, message := range request.Messages {
		if message.Role == "user" && !isCloudTranscriptDateReminder(message.Content) {
			users = append(users, message.Content)
		}
		for _, call := range message.ToolCalls {
			if toolIndex != -1 || message.Role != "assistant" || call.ID != cloudTranscriptCall || call.Function.Name != "Read" || call.Extra.Google.Signature != cloudTranscriptSignature {
				return fmt.Errorf("round %d tool identity or signature changed", round)
			}
			var args map[string]string
			if json.Unmarshal([]byte(call.Function.Arguments), &args) != nil || len(args) != 1 || args["file_path"] != witness {
				return fmt.Errorf("round %d tool arguments changed", round)
			}
			toolIndex = index
		}
		if message.Role == "tool" {
			if resultIndex != -1 || message.ToolCallID != cloudTranscriptCall || !strings.Contains(message.Content, cloudTranscriptMarker) {
				return fmt.Errorf("round %d tool result changed: prior=%d call=%q content=%q", round, resultIndex, message.ToolCallID, message.Content)
			}
			resultIndex = index
		}
	}
	if round == 1 && len(users) == 1 && users[0] == cloudTranscriptFirst && toolIndex == -1 && resultIndex == -1 {
		return nil
	}
	if toolIndex < 0 || resultIndex != toolIndex+1 {
		return fmt.Errorf("round %d tool history order changed", round)
	}
	if round == 2 && len(users) == 1 && users[0] == cloudTranscriptFirst && resultIndex == len(request.Messages)-1 {
		return nil
	}
	if round == 3 && len(users) == 2 && users[0] == cloudTranscriptFirst && users[1] == cloudTranscriptResume &&
		resultIndex+2 == len(request.Messages)-1 && request.Messages[resultIndex+1].Role == "assistant" && request.Messages[resultIndex+1].Content == cloudTranscriptFirstReply && request.Messages[len(request.Messages)-1].Role == "user" {
		return nil
	}
	return fmt.Errorf("round %d transcript progression changed", round)
}

func writeCloudTranscriptResponse(w http.ResponseWriter, stream bool, round int32, witness string) {
	message := map[string]any{"role": "assistant"}
	finish := "stop"
	switch round {
	case 1:
		finish = "tool_calls"
		args, _ := json.Marshal(map[string]string{"file_path": witness})
		tool := map[string]any{"id": cloudTranscriptCall, "type": "function", "function": map[string]string{"name": "Read", "arguments": string(args)}, "extra_content": map[string]any{"google": map[string]string{"thought_signature": cloudTranscriptSignature}}}
		if stream {
			tool["index"] = 0
		}
		message["tool_calls"] = []any{tool}
	case 2:
		message["content"] = cloudTranscriptFirstReply
	case 3:
		message["content"] = cloudTranscriptResumeReply
	}
	if stream {
		w.Header().Set("Content-Type", "text/event-stream")
		frame := func(delta map[string]any, reason any) {
			data, _ := json.Marshal(map[string]any{"choices": []any{map[string]any{"index": 0, "delta": delta, "finish_reason": reason}}})
			_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
		}
		frame(message, nil)
		frame(map[string]any{}, finish)
		_, _ = io.WriteString(w, "data: [DONE]\n\n")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": message, "finish_reason": finish}}})
}

func isCloudTranscriptDateReminder(content string) bool {
	rest, ok := strings.CutPrefix(content, "<system-reminder>\n# currentDate\nToday's date is ")
	if !ok {
		return false
	}
	date, ok := strings.CutSuffix(rest, ".\n</system-reminder>")
	if !ok {
		return false
	}
	_, err := time.Parse("2006-01-02", date)
	return err == nil
}

func validCloudTranscriptEndpoint(base string) bool {
	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme != "http" || parsed.Hostname() != "127.0.0.1" || parsed.User != nil ||
		strings.ContainsAny(base, "?#") || parsed.EscapedPath() != "/v1beta/openai/" {
		return false
	}
	port, err := strconv.Atoi(parsed.Port())
	return err == nil && port > 0 && port <= 65535
}

func TestManagedCloudCompatibilityChatTranscriptEndpoint(t *testing.T) {
	if !validCloudTranscriptEndpoint("http://127.0.0.1:12345/v1beta/openai/") {
		t.Fatal("fixture endpoint rejected")
	}
	for _, value := range []string{
		"http://127.0.0.1:123@other.invalid/v1beta/openai/",
		"http://user@127.0.0.1:123/v1beta/openai/",
		"http://127.0.0.1:0/v1beta/openai/",
		"http://127.0.0.1:123/v1beta/openai/?",
		"http://127.0.0.1:123/v1beta/openai/#",
		"http://127.0.0.1:123/v1beta/other/",
	} {
		if validCloudTranscriptEndpoint(value) {
			t.Errorf("unsafe fixture endpoint accepted: %s", value)
		}
	}
}
