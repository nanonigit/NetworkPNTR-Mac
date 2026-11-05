package server

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Autumn-27/artex/agent"
	"github.com/Autumn-27/artex/db"
)

func TestManagedCloudCredentialTarget(t *testing.T) {
	dsn := os.Getenv("ARTEX_CREDENTIAL_TEST_DSN")
	if dsn == "" {
		t.Skip("isolated PostgreSQL credential fixture is unavailable")
	}
	database, err := db.Open(dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = database.Close() })

	var hits, storedKeyHits, newKeyHits atomic.Int32
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		switch r.Header.Get("Authorization") {
		case "Bearer fixture-stored-key":
			storedKeyHits.Add(1)
		case "Bearer fixture-new-key":
			newKeyHits.Add(1)
		}
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodGet {
			_, _ = fmt.Fprint(w, `{"data":[{"id":"fixture"}]}`)
		} else if strings.HasSuffix(r.URL.Path, "/chat/completions") {
			_, _ = fmt.Fprint(w, `{"choices":[{"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}`)
		} else {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = fmt.Fprint(w, `{"error":{"message":"fixture route unavailable"}}`)
		}
	}))
	defer provider.Close()
	profile := db.LLMProfile{
		Name: "credential-target-fixture", Format: "openai", BaseURL: provider.URL + "/original",
		Model: "fixture", APIKey: "fixture-stored-key",
	}
	id, err := database.SaveProfile(&profile)
	if err != nil {
		t.Fatal(err)
	}
	profile.ID = id
	t.Cleanup(func() {
		// The test database is disposable. Keep repeated runs independent too.
		_, _ = database.Exec("DELETE FROM llm_profiles WHERE id=$1", id)
	})
	server := &Server{
		m:      &Manager{pg: database},
		llmCfg: agent.ConfigFrom("openai", "fixture", profile.BaseURL, profile.APIKey, ""),
	}

	request := func(t *testing.T, handler http.HandlerFunc, input any) (int, bool) {
		t.Helper()
		payload, err := json.Marshal(input)
		if err != nil {
			t.Fatal(err)
		}
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(payload)))
		var result struct {
			OK bool `json:"ok"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		return recorder.Code, result.OK
	}
	for name, handler := range map[string]http.HandlerFunc{"discovery": server.pgListModels, "connection": server.testLLM} {
		t.Run(name, func(t *testing.T) {
			for _, target := range []struct {
				format, url, proxy string
			}{
				{"openai", provider.URL + "/different-tenant", ""},
				{"openai-responses", profile.BaseURL, ""},
				{"openai", profile.BaseURL, provider.URL},
			} {
				before := hits.Load()
				_, ok := request(t, handler, map[string]any{
					"provider": target.format, "base_url": target.url, "proxy": target.proxy,
					"profile_id": id, "model": "fixture", "streaming": false,
				})
				if ok || hits.Load() != before {
					t.Errorf("modified target sent %d requests", hits.Load()-before)
				}
			}
			before := storedKeyHits.Load()
			_, ok := request(t, handler, map[string]any{
				"provider": "openai", "base_url": profile.BaseURL + "/", "profile_id": id,
				"model": "fixture", "streaming": false,
			})
			if !ok || storedKeyHits.Load() != before+1 {
				t.Error("unchanged target did not use the saved key")
			}
			before = newKeyHits.Load()
			_, ok = request(t, handler, map[string]any{
				"provider": "openai", "base_url": provider.URL + "/different-tenant", "profile_id": id,
				"api_key": "fixture-new-key", "model": "fixture", "streaming": false,
			})
			if !ok || newKeyHits.Load() != before+1 {
				t.Error("explicit key did not authorize the edited target")
			}
		})
	}
	t.Run("global fallback", func(t *testing.T) {
		for _, input := range []map[string]any{
			{"provider": "openai", "model": "fixture", "base_url": provider.URL + "/different-tenant", "streaming": false},
			{"provider": "openai", "model": "fixture", "base_url": profile.BaseURL, "streaming": false, "profile_id": -1},
		} {
			before := hits.Load()
			_, ok := request(t, server.testLLM, input)
			if ok || hits.Load() != before {
				t.Error("global credential fallback sent a request outside its scope")
			}
		}
		before := storedKeyHits.Load()
		_, ok := request(t, server.testLLM, map[string]any{
			"provider": "openai", "model": "fixture", "base_url": profile.BaseURL, "streaming": false,
		})
		if !ok || storedKeyHits.Load() != before+1 {
			t.Error("global credential was not reused at the original target")
		}
		code, _ := request(t, server.setLLM, map[string]any{
			"provider": "openai", "model": "fixture", "base_url": provider.URL + "/different-tenant",
		})
		if code != http.StatusBadRequest {
			t.Error("legacy configuration accepted a changed target with a blank key")
		}
	})
	t.Run("blank-key save", func(t *testing.T) {
		update := map[string]any{
			"id": id, "name": profile.Name, "format": "openai", "base_url": provider.URL + "/different-tenant", "model": "fixture",
		}
		code, _ := request(t, server.pgSaveProfile, update)
		got, err := database.ProfileByID(id)
		if err != nil || got == nil {
			t.Fatal("cannot reload fixture profile")
		}
		if code != http.StatusBadRequest || got.BaseURL != profile.BaseURL || got.APIKey != profile.APIKey {
			t.Fatal("blank-key update moved the stored key")
		}
		update["name"], update["base_url"] = "renamed", profile.BaseURL+"/"
		code, _ = request(t, server.pgSaveProfile, update)
		got, err = database.ProfileByID(id)
		if err != nil || got == nil || code != http.StatusOK || got.Name != "renamed" || got.APIKey != profile.APIKey {
			t.Fatal("same-target rename did not preserve the key")
		}
	})
	t.Run("concurrent key and target replacement", func(t *testing.T) {
		replacementURL := provider.URL + "/replacement"
		tx, err := database.BeginTx(t.Context(), nil)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback()
		if _, err := tx.Exec("UPDATE llm_profiles SET base_url=$1, api_key=$2 WHERE id=$3", replacementURL, "fixture-new-key", id); err != nil {
			t.Fatal(err)
		}
		done := make(chan error, 1)
		go func() {
			update := profile
			update.APIKey = ""
			_, err := database.SaveProfile(&update)
			done <- err
		}()
		deadline := time.Now().Add(5 * time.Second)
		for {
			var waiting bool
			err := database.QueryRow(`SELECT EXISTS (
				SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock'
			)`).Scan(&waiting)
			if err != nil {
				t.Fatal(err)
			}
			if waiting {
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("blank-key update did not wait for the concurrent write")
			}
			time.Sleep(10 * time.Millisecond)
		}
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
		select {
		case err := <-done:
			if !errors.Is(err, db.ErrLLMCredentialTargetChanged) {
				t.Fatal("blank-key update did not reject the committed target")
			}
		case <-time.After(5 * time.Second):
			t.Fatal("blank-key update did not complete")
		}
		got, err := database.ProfileByID(id)
		if err != nil || got == nil || got.BaseURL != replacementURL || got.APIKey != "fixture-new-key" {
			t.Fatal("concurrent update did not retain the replacement target and key")
		}
	})
	t.Run("discovery candidate paths", func(t *testing.T) {
		var siblingHits, doubleSlashHits atomic.Int32
		gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			switch r.URL.Path {
			case "/tenant/anthropic/v1/models":
				w.WriteHeader(http.StatusNotFound)
			case "/tenant/models", "/tenant/v1/models":
				siblingHits.Add(1)
				_, _ = fmt.Fprint(w, `{"data":[{"id":"sibling"}]}`)
			case "/tenant/responses/models":
				_, _ = fmt.Fprint(w, `{"data":[{"id":"original"}]}`)
			case "/tenant/responses//models":
				doubleSlashHits.Add(1)
				_, _ = fmt.Fprint(w, `{"data":[{"id":"original"}]}`)
			default:
				w.WriteHeader(http.StatusNotFound)
			}
		}))
		defer gateway.Close()
		for _, target := range []struct {
			format, path string
			ok           bool
		}{
			{"anthropic", "/tenant/anthropic", false},
			{"openai", "/tenant/responses", true},
		} {
			stored := db.LLMProfile{Name: "candidate-" + target.format, Format: target.format, BaseURL: gateway.URL + target.path, Model: "fixture", APIKey: "fixture-stored-key"}
			targetID, err := database.SaveProfile(&stored)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _, _ = database.Exec("DELETE FROM llm_profiles WHERE id=$1", targetID) })
			before := siblingHits.Load()
			_, ok := request(t, server.pgListModels, map[string]any{
				"provider": target.format, "base_url": stored.BaseURL, "profile_id": targetID,
			})
			if ok != target.ok || siblingHits.Load() != before {
				t.Errorf("saved %s key tried %d sibling requests", target.format, siblingHits.Load()-before)
			}
		}
		before := siblingHits.Load()
		_, ok := request(t, server.pgListModels, map[string]any{
			"provider": "anthropic", "base_url": gateway.URL + "/tenant/anthropic", "api_key": "fixture-new-key",
		})
		if !ok || siblingHits.Load() != before+1 {
			t.Error("explicit-key legacy discovery fallback did not work")
		}
		t.Setenv("OPENAI_BASE_URL", gateway.URL+"/tenant/responses")
		defaultID, err := database.SaveProfile(&db.LLMProfile{
			Name: "candidate-default", Format: "openai", Model: "fixture", APIKey: "fixture-stored-key",
		})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _, _ = database.Exec("DELETE FROM llm_profiles WHERE id=$1", defaultID) })
		_, ok = request(t, server.pgListModels, map[string]any{"provider": "openai", "profile_id": defaultID})
		if !ok {
			t.Error("saved default key did not use the completion client's configured base")
		}
		t.Setenv("OPENAI_BASE_URL", gateway.URL+"/tenant/responses/")
		_, ok = request(t, server.pgListModels, map[string]any{"provider": "openai", "profile_id": defaultID})
		if !ok || doubleSlashHits.Load() != 1 {
			t.Error("saved default key lost the configured trailing slash")
		}
		t.Setenv("OPENAI_BASE_URL", "/")
		if savedLLMModelsBase("openai", "") != "/" {
			t.Error("invalid override must not be converted into the public default")
		}
	})
}
