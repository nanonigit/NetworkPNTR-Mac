package server

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Autumn-27/artex/traffic"
)

func managedBlobServer(t *testing.T) (*Server, *traffic.Traffic, string, []byte, string) {
	t.Helper()
	dir := t.TempDir()
	tr, err := traffic.Open(dir, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { tr.Close() })
	body := bytes.Repeat([]byte{0, 1, 0xff, 'x'}, 65537)
	hash := fmt.Sprintf("%x", sha256.Sum256(body))
	path := filepath.Join(dir, "_blobs", "sha256", hash[:2], hash+".bin")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, body, 0600); err != nil {
		t.Fatal(err)
	}
	id := "\ufeffe\u0301 中文 한국어"
	if _, err := tr.DB().Exec("INSERT INTO exchanges(id,req_len,resp_len) VALUES(?,?,?)", id, 0, len(body)); err != nil {
		t.Fatal(err)
	}
	if _, err := tr.DB().Exec("INSERT INTO exchange_bodies(id,resp_blob) VALUES(?,?)", id, hash); err != nil {
		t.Fatal(err)
	}
	s := &Server{m: &Manager{traffic: tr}, jwtKey: []byte("managed-blob-test-only-key")}
	token, err := signJWT(s.jwtKey)
	if err != nil {
		t.Fatal(err)
	}
	return s, tr, token, body, path
}

func managedBlobRequest(s *Server, method, route, token string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, route, nil)
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response := httptest.NewRecorder()
	s.Handler().ServeHTTP(response, request)
	return response
}

func TestManagedBlobHTTPAuthMetadataAndOriginalBytes(t *testing.T) {
	s, _, token, body, _ := managedBlobServer(t)
	id := "\ufeffe\u0301 中文 한국어"
	route := "/api/traffic/blob-metadata?id=" + url.QueryEscape(id) + "&side=response"
	for _, auth := range []string{"", "invalid-token"} {
		if r := managedBlobRequest(s, "GET", route, auth); r.Code != 401 {
			t.Fatalf("unauthorized metadata: %d", r.Code)
		}
	}
	response := managedBlobRequest(s, "GET", route, token)
	if response.Code != 200 {
		t.Fatalf("metadata status %d: %s", response.Code, response.Body)
	}
	var manifest traffic.BlobManifest
	if err := json.Unmarshal(response.Body.Bytes(), &manifest); err != nil {
		t.Fatal(err)
	}
	hash := fmt.Sprintf("%x", sha256.Sum256(body))
	if manifest.ID != id || manifest.Side != "response" || manifest.Hash != hash || manifest.Size != int64(len(body)) {
		t.Fatal("wrong manifest")
	}
	if response.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("metadata cache policy")
	}
	blob := "/api/traffic/blob?hash=" + hash
	if r := managedBlobRequest(s, "GET", blob, ""); r.Code != 401 {
		t.Fatal("blob unauthenticated")
	}
	download := managedBlobRequest(s, "GET", blob, token)
	if download.Code != 200 || !bytes.Equal(download.Body.Bytes(), body) || download.Header().Get("Content-Length") != fmt.Sprint(len(body)) {
		t.Fatal("original bytes differ")
	}
}

func TestManagedBlobHTTPRejectsInvalidScopeAndMissingBodies(t *testing.T) {
	s, _, token, _, _ := managedBlobServer(t)
	for _, query := range []string{"", "id=x", "id=x&side=Response", "id=x&side=request&side=response", "id=x&id=y&side=response", "id=x&side=response&url=http://outside.invalid", "id=%0A&side=response", "id=%zz&side=response"} {
		r := managedBlobRequest(s, "GET", "/api/traffic/blob-metadata?"+query, token)
		if r.Code != 400 {
			t.Fatalf("bad query %q: %d", query, r.Code)
		}
	}
	for _, query := range []string{"id=missing&side=response", "id=" + url.QueryEscape("\ufeffe\u0301 中文 한국어") + "&side=request"} {
		if r := managedBlobRequest(s, "GET", "/api/traffic/blob-metadata?"+query, token); r.Code != 404 {
			t.Fatal("missing/inline body not unavailable", r.Code)
		}
	}
	if r := managedBlobRequest(s, "POST", "/api/traffic/blob-metadata?id=x&side=response", token); r.Code != 405 {
		t.Fatal("write method accepted")
	}
}

func TestManagedBlobHTTPStorageFailureIsNotAbsentBody(t *testing.T) {
	s, tr, token, _, _ := managedBlobServer(t)
	if err := tr.DB().Close(); err != nil {
		t.Fatal(err)
	}
	r := managedBlobRequest(s, "GET", "/api/traffic/blob-metadata?id=x&side=response", token)
	if r.Code != 503 || strings.Contains(r.Body.String(), "sql:") {
		t.Fatal("storage failure misclassified or leaked", r.Code)
	}
}

func TestManagedBlobHTTPRefusesSymlinkAtStreamingBoundary(t *testing.T) {
	s, _, token, body, path := managedBlobServer(t)
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	other := filepath.Join(t.TempDir(), "unrelated.bin")
	if err := os.WriteFile(other, body, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(other, path); err != nil {
		t.Fatal(err)
	}
	hash := fmt.Sprintf("%x", sha256.Sum256(body))
	r := managedBlobRequest(s, "GET", "/api/traffic/blob?hash="+hash, token)
	if r.Code != http.StatusNotFound || bytes.Equal(r.Body.Bytes(), body) {
		t.Fatal("stream followed a symlink")
	}
}

func TestManagedBlobHTTPLegacyHashCompatibility(t *testing.T) {
	s, _, token, body, _ := managedBlobServer(t)
	hash := fmt.Sprintf("%x", sha256.Sum256(body))
	for _, value := range []string{strings.ToUpper(hash), " \t" + strings.ToUpper(hash) + "\n "} {
		r := managedBlobRequest(s, "GET", "/api/traffic/blob?hash="+url.QueryEscape(value), token)
		if r.Code != 200 || !bytes.Equal(r.Body.Bytes(), body) {
			t.Fatal("legacy hash normalization changed", r.Code)
		}
	}
}
