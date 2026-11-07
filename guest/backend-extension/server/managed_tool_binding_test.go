package server

import (
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

func TestManagedToolBindingRejectsInvalidRequestsBeforeDatabaseAccess(t *testing.T) {
	for _, tc := range []struct{ agent, tool, body, query string }{
		{"worker", "record_fact", "", ""},
		{"worker", "record_fact", "null", ""},
		{"worker", "record_fact", "true false", ""},
		{"worker", "record_fact", strings.Repeat(" ", 64) + "true", ""},
		{"worker", "record_fact", "false", "?unexpected=1"},
		{"../worker", "record_fact", "true", ""},
		{"worker", "../tool", "false", ""},
	} {
		request := httptest.NewRequest(http.MethodPut, "/"+tc.query, strings.NewReader(tc.body))
		request.SetPathValue("key", tc.agent)
		request.SetPathValue("tool", tc.tool)
		response := httptest.NewRecorder()
		(&Server{}).putManagedToolBinding(response, request)
		if response.Code != http.StatusBadRequest {
			t.Fatalf("invalid request returned %d", response.Code)
		}
	}
}

func TestManagedToolBindingPostgres(t *testing.T) {
	dsn := os.Getenv("ARTEX_MANAGED_TOOL_BINDING_TEST_DSN")
	if dsn == "" {
		t.Skip("dedicated tool-binding fixture database not configured")
	}
	pg, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pg.Close()
	exec := func(query string) {
		t.Helper()
		if _, err := pg.Exec(query); err != nil {
			t.Fatal(err)
		}
	}
	// A fresh disposable database is required. Never drop or alter existing tables.
	exec(`CREATE TABLE agents(key text PRIMARY KEY);
CREATE TABLE settings(key text PRIMARY KEY, value text NOT NULL);
CREATE TABLE tools(key text PRIMARY KEY, agents jsonb NOT NULL, description text, enabled boolean, schema jsonb, exec jsonb);
INSERT INTO agents VALUES ('one'), ('two'), ('other');
INSERT INTO tools VALUES ('test_tool', '["other"]', 'keep', false, '{"x":2}', '{"y":3}'),
    ('traffic_search', '[]', 'traffic', true, '{}', '{}'), ('legacy_tool', 'null', 'legacy', true, '{}', '{}'),
    ('malformed_tool', '[1]', 'bad', true, '{}', '{}');`)
	check := func(agent, tool string, desired bool, status int) {
		t.Helper()
		got, err := setManagedToolBinding(context.Background(), pg, agent, tool, desired)
		if got != status || (err == nil) != (status == http.StatusOK) {
			t.Errorf("%s/%s: got %d (%v), want %d", agent, tool, got, err, status)
		}
	}
	var concurrent sync.WaitGroup
	for _, agent := range []string{"one", "two"} {
		concurrent.Go(func() { check(agent, "test_tool", true, http.StatusOK) })
	}
	concurrent.Wait()
	check("one", "test_tool", true, http.StatusOK)
	var preserved bool
	err = pg.QueryRow(`SELECT jsonb_array_length(agents) = 3 AND agents ?& ARRAY['one','two','other']
AND description = 'keep' AND NOT enabled AND schema = '{"x":2}' AND exec = '{"y":3}'
FROM tools WHERE key = 'test_tool'`).Scan(&preserved)
	if err != nil || !preserved {
		t.Fatalf("concurrent memberships or unrelated columns lost: %v", err)
	}
	check("one", "test_tool", false, http.StatusOK)
	check("one", "test_tool", false, http.StatusOK)
	err = pg.QueryRow(`SELECT jsonb_array_length(agents) = 2 AND agents ?& ARRAY['two','other']
FROM tools WHERE key = 'test_tool'`).Scan(&preserved)
	if err != nil || !preserved {
		t.Fatalf("removal changed another membership: %v", err)
	}
	check("unknown", "test_tool", true, http.StatusNotFound)
	check("one", "unknown", true, http.StatusNotFound)
	check("one", "malformed_tool", true, http.StatusConflict)
	check("one", "legacy_tool", false, http.StatusOK)
	check("one", "legacy_tool", true, http.StatusOK)
	check("one", "legacy_tool", false, http.StatusOK)
	check("one", "traffic_search", true, http.StatusConflict)
	exec("INSERT INTO settings VALUES ('traffic_capture', 'true')")
	check("one", "traffic_search", true, http.StatusOK)
	exec("UPDATE settings SET value = 'false'")
	check("one", "traffic_search", false, http.StatusConflict)
	err = pg.QueryRow(`SELECT agents = '["one"]' FROM tools WHERE key = 'traffic_search'`).Scan(&preserved)
	if err != nil || !preserved {
		t.Fatalf("disabled capture changed the binding: %v", err)
	}
}
