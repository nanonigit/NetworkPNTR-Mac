package server

import (
	"bytes"
	"encoding/json"
	"golang.org/x/crypto/bcrypt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

func nativeRequest(s *Server, peer, origin, target, body string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodPost, target, bytes.NewBufferString(body))
	request.RemoteAddr = peer
	request.Header.Set("Content-Type", "application/json")
	if origin != "" {
		request.Header.Set("Origin", origin)
	}
	response := httptest.NewRecorder()
	s.nativeLocalSession(response, request)
	return response
}

func TestNativeCapabilityConsumedAndUnset(t *testing.T) {
	for _, value := range []string{"", "private-invalid", strings.Repeat("A", 64), strings.Repeat("a", 63), strings.Repeat("b", 64)} {
		t.Setenv("NETWORKPNTR_LOCAL_SESSION_CAPABILITY", value)
		got := consumeNativeSessionCapability()
		if _, exists := os.LookupEnv("NETWORKPNTR_LOCAL_SESSION_CAPABILITY"); exists {
			t.Fatal("capability inherited by subprocess environment")
		}
		if value == strings.Repeat("b", 64) {
			if got != value {
				t.Fatal("valid capability rejected")
			}
		} else if got != "" {
			t.Fatal("invalid capability accepted")
		}
	}
}

func TestNativeSessionRejectsUntrustedRequestsBeforeDatabase(t *testing.T) {
	capability := strings.Repeat("a", 64)
	cases := []struct {
		name, key, peer, origin, target, body string
		status                                int
	}{
		{"disabled", "", "127.0.0.1:1234", "", "/api/auth/local-session", `{}`, 404},
		{"external", capability, "192.0.2.1:1234", "", "/api/auth/local-session", `{"capability":"` + capability + `"}`, 403},
		{"origin", capability, "127.0.0.1:1234", "https://example.invalid", "/api/auth/local-session", `{"capability":"` + capability + `"}`, 403},
		{"query", capability, "127.0.0.1:1234", "", "/api/auth/local-session?capability=private", `{"capability":"` + capability + `"}`, 400},
		{"wrong", capability, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"` + strings.Repeat("b", 64) + `"}`, 403},
		{"extra", capability, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"` + capability + `","extra":"private"}`, 400},
		{"trailing", capability, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"` + capability + `"} {}`, 400},
		{"oversize", capability, "127.0.0.1:1234", "", "/api/auth/local-session", strings.Repeat(" ", 513), 400},
		{"no_database", capability, "[::1]:1234", "", "/api/auth/local-session", `{"capability":"` + capability + `"}`, 503},
	}
	for _, item := range cases {
		t.Run(item.name, func(t *testing.T) {
			s := &Server{nativeSessionKey: item.key, jwtKey: []byte(strings.Repeat("j", 32))}
			response := nativeRequest(s, item.peer, item.origin, item.target, item.body)
			if response.Code != item.status {
				t.Fatalf("status=%d want=%d", response.Code, item.status)
			}
			if strings.Contains(response.Body.String(), capability) || strings.Contains(response.Body.String(), "private") {
				t.Fatal("secret reflected in response")
			}
			if response.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("response may be cached")
			}
		})
	}
}

func nativeDatabaseToken(t *testing.T, s *Server) string {
	t.Helper()
	response := nativeRequest(s, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"`+s.nativeSessionKey+`"}`)
	if response.Code != 200 {
		t.Fatalf("local session status=%d", response.Code)
	}
	var reply struct {
		Token string `json:"token"`
	}
	if json.Unmarshal(response.Body.Bytes(), &reply) != nil || reply.Token == "" || !s.verifyToken(reply.Token) {
		t.Fatal("missing or invalid session")
	}
	return reply.Token
}

func TestNativeSessionInitializesOnceAndPreservesStoredHashDB(t *testing.T) {
	rig := newAuthTestRig(t)
	rig.s.nativeSessionKey = strings.Repeat("a", 64)
	nativeDatabaseToken(t, rig.s)
	first, _, err := rig.s.m.pg.GetSetting(authPassKey)
	if err != nil {
		t.Fatal("read persisted hash")
	}
	if _, err := bcrypt.Cost([]byte(first)); err != nil {
		t.Fatal("invalid internal hash")
	}
	nativeDatabaseToken(t, rig.s)
	second, _, err := rig.s.m.pg.GetSetting(authPassKey)
	if err != nil || first != second {
		t.Fatal("persisted hash changed")
	}
}

func TestNativeSessionPreservesLegacyHashAndTokenDB(t *testing.T) {
	rig := newAuthTestRig(t)
	hash, err := bcrypt.GenerateFromPassword([]byte("fixture-internal-password"), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := rig.s.m.pg.Exec(`INSERT INTO settings(key,value) VALUES($1,$2)`, authPassKey, string(hash)); err != nil {
		t.Fatal(err)
	}
	rig.s.setPassHash(string(hash))
	previous, err := signJWT(rig.s.signingKey(string(hash)))
	if err != nil {
		t.Fatal(err)
	}
	rig.s.nativeSessionKey = strings.Repeat("a", 64)
	nativeDatabaseToken(t, rig.s)
	current, _, err := rig.s.m.pg.GetSetting(authPassKey)
	if err != nil || current != string(hash) || !rig.s.verifyToken(previous) {
		t.Fatal("legacy credential changed")
	}
	// A fresh boot changes the capability, while existing database credentials stay intact.
	rig.s.nativeSessionKey = strings.Repeat("b", 64)
	rejected := nativeRequest(rig.s, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"`+strings.Repeat("a", 64)+`"}`)
	if rejected.Code != 403 {
		t.Fatal("old boot capability accepted")
	}
	nativeDatabaseToken(t, rig.s)
}

func TestNativeSessionRejectsMalformedHashDB(t *testing.T) {
	rig := newAuthTestRig(t)
	if _, err := rig.s.m.pg.Exec(`INSERT INTO settings(key,value) VALUES($1,$2)`, authPassKey, "corrupt"); err != nil {
		t.Fatal(err)
	}
	rig.s.nativeSessionKey = strings.Repeat("a", 64)
	reply := nativeRequest(rig.s, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"`+rig.s.nativeSessionKey+`"}`)
	if reply.Code != 503 || strings.Contains(reply.Body.String(), "token") {
		t.Fatal("malformed hash issued session")
	}
}

func TestNativeSessionConcurrentInitializersUsePersistedWinnerDB(t *testing.T) {
	rig := newAuthTestRig(t)
	servers := []*Server{rig.s, {m: rig.s.m, jwtKey: rig.s.jwtKey}}
	var group sync.WaitGroup
	replies := make([]*httptest.ResponseRecorder, 2)
	for i, s := range servers {
		s.nativeSessionKey = strings.Repeat("a", 64)
		group.Add(1)
		go func(index int, server *Server) {
			defer group.Done()
			replies[index] = nativeRequest(server, "127.0.0.1:1234", "", "/api/auth/local-session", `{"capability":"`+server.nativeSessionKey+`"}`)
		}(i, s)
	}
	group.Wait()
	hash, _, err := rig.s.m.pg.GetSetting(authPassKey)
	if err != nil || hash == "" {
		t.Fatal("missing persisted winner")
	}
	for i, reply := range replies {
		var value struct {
			Token string `json:"token"`
		}
		if reply.Code != 200 || json.Unmarshal(reply.Body.Bytes(), &value) != nil || !servers[i].verifyToken(value.Token) {
			t.Fatal("initializer did not use persisted winner")
		}
	}
}
