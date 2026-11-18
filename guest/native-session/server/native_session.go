package server

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net"
	"net/http"
	"os"
	"time"

	"golang.org/x/crypto/bcrypt"
)

const nativeSessionEnvironment = "NETWORKPNTR_LOCAL_SESSION_CAPABILITY"

func consumeNativeSessionCapability() string {
	value := os.Getenv(nativeSessionEnvironment)
	_ = os.Unsetenv(nativeSessionEnvironment)
	if len(value) != 64 {
		return ""
	}
	for _, c := range []byte(value) {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return ""
		}
	}
	return value
}

// This route is enabled only by the private, per-boot native provisioning frame.
// It preserves API JWT checks and never accepts a user-selected identity/password.
func (s *Server) nativeLocalSession(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if s.nativeSessionKey == "" {
		writeErr(w, 404, "Local connection unavailable")
		return
	}
	if r.Method != http.MethodPost {
		writeErr(w, 405, "Unsupported method")
		return
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() || r.Header.Get("Origin") != "" {
		writeErr(w, 403, "Local connection denied")
		return
	}
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if r.URL.RawQuery != "" || err != nil || media != "application/json" || r.Body == nil {
		writeErr(w, 400, "Invalid local connection request")
		return
	}
	var body struct {
		Capability string `json:"capability"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 512))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&body) != nil || decoder.Decode(new(any)) != io.EOF {
		writeErr(w, 400, "Invalid local connection request")
		return
	}
	if len(body.Capability) != 64 || subtle.ConstantTimeCompare([]byte(body.Capability), []byte(s.nativeSessionKey)) != 1 {
		writeErr(w, 403, "Local connection denied")
		return
	}
	if s.m == nil || s.m.pg == nil {
		writeErr(w, 503, "Local connection unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	readHash := func() (string, error) {
		var hash string
		err := s.m.pg.QueryRowContext(ctx, `SELECT value FROM settings WHERE key = $1`, authPassKey).Scan(&hash)
		if errors.Is(err, sql.ErrNoRows) {
			return "", nil
		}
		return hash, err
	}
	hash, err := readHash()
	if err != nil {
		writeErr(w, 503, "Local connection unavailable")
		return
	}
	if hash == "" {
		internal, err := randomToken(48)
		if err != nil {
			writeErr(w, 503, "Local connection unavailable")
			return
		}
		generated, err := bcrypt.GenerateFromPassword([]byte(internal), bcrypt.DefaultCost)
		if err != nil {
			writeErr(w, 503, "Local connection unavailable")
			return
		}
		_, err = s.m.pg.ExecContext(ctx, `INSERT INTO settings(key, value) VALUES ($1, $2) ON CONFLICT (key) DO NOTHING`, authPassKey, string(generated))
		if err != nil {
			writeErr(w, 503, "Local connection unavailable")
			return
		}
		// A different initializer may have won: sign only with the persisted hash.
		hash, err = readHash()
		if err != nil || hash == "" {
			writeErr(w, 503, "Local connection unavailable")
			return
		}
	}
	if ctx.Err() != nil {
		writeErr(w, 503, "Local connection unavailable")
		return
	}
	if _, err := bcrypt.Cost([]byte(hash)); err != nil {
		writeErr(w, 503, "Local connection unavailable")
		return
	}
	s.setPassHash(hash)
	s.clearSetupToken()
	token, err := signJWT(s.signingKey(hash))
	if err != nil {
		writeErr(w, 503, "Local connection unavailable")
		return
	}
	writeJSON(w, 200, map[string]any{"token": token})
}
