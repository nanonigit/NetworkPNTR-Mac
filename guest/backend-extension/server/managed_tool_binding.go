package server

import (
	"context"
	"database/sql"
	"errors"
	"io"
	"net/http"
	"strings"
)

func (s *Server) putManagedToolBinding(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	agent, tool := r.PathValue("key"), r.PathValue("tool")
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64))
	value := strings.Trim(string(body), " \t\r\n")
	if err != nil || !reAgentKey.MatchString(agent) || !reToolKey.MatchString(tool) ||
		(value != "true" && value != "false") || r.URL.RawQuery != "" {
		writeErr(w, http.StatusBadRequest, "invalid tool binding")
		return
	}
	pg := s.pg(w)
	if pg == nil {
		return
	}

	bound := value == "true"
	status, err := setManagedToolBinding(r.Context(), pg.DB, agent, tool, bound)
	if err != nil {
		writeErr(w, status, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"agent": agent, "tool": tool, "bound": bound})
}

func setManagedToolBinding(ctx context.Context, pg *sql.DB, agent, tool string, bound bool) (int, error) {
	unavailable := errors.New("tool binding storage unavailable")
	tx, err := pg.BeginTx(ctx, nil)
	if err != nil {
		return http.StatusServiceUnavailable, unavailable
	}
	defer tx.Rollback()

	var found string
	err = tx.QueryRowContext(ctx, "SELECT key FROM agents WHERE key = $1 FOR KEY SHARE", agent).Scan(&found)
	if errors.Is(err, sql.ErrNoRows) {
		return http.StatusNotFound, errors.New("agent not found")
	}
	if err != nil {
		return http.StatusServiceUnavailable, unavailable
	}
	if tool == "traffic_search" || tool == "traffic_get" {
		var gate string
		err = tx.QueryRowContext(ctx, "SELECT value FROM settings WHERE key = $1 FOR SHARE", settingTrafficCapture).Scan(&gate)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return http.StatusServiceUnavailable, unavailable
		}
		if gate != "true" && gate != "1" {
			return http.StatusConflict, errors.New("traffic capture is disabled")
		}
	}

	var kind string
	var current, invalidElement bool
	err = tx.QueryRowContext(ctx, `
SELECT jsonb_typeof(agents), agents ? $2::text,
       jsonb_path_exists(agents, '$[*] ? (@.type() != "string")')
FROM tools WHERE key = $1 FOR UPDATE`, tool, agent).Scan(&kind, &current, &invalidElement)
	if errors.Is(err, sql.ErrNoRows) {
		return http.StatusNotFound, errors.New("tool not found")
	}
	if err != nil {
		return http.StatusServiceUnavailable, unavailable
	}
	if kind != "null" && (kind != "array" || invalidElement) {
		return http.StatusConflict, errors.New("invalid stored tool bindings")
	}
	if current != bound {
		_, err = tx.ExecContext(ctx, `
UPDATE tools SET agents = CASE
	WHEN $3::boolean THEN COALESCE(NULLIF(agents, 'null'::jsonb), '[]'::jsonb) || jsonb_build_array($2::text)
	ELSE agents - $2::text
END WHERE key = $1`, tool, agent, bound)
		if err != nil {
			return http.StatusServiceUnavailable, unavailable
		}
	}
	if err := tx.Commit(); err != nil {
		return http.StatusServiceUnavailable, unavailable
	}
	return http.StatusOK, nil
}
