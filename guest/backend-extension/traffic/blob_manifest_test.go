package traffic

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestManagedBlobManifestBothSides(t *testing.T) {
	tr, _ := openTraffic(t)
	request, response := bytes.Repeat([]byte("r"), maxInlineBody+1), bytes.Repeat([]byte("s"), maxInlineBody+2)
	tr.record(newFlow("fixture.invalid", "POST", "/", request, response))
	id := onlyExchangeID(t, tr)
	for _, tc := range []struct {
		side string
		body []byte
	}{{"request", request}, {"response", response}} {
		value, err := tr.BlobManifest(id, tc.side)
		if err != nil {
			t.Fatal(err)
		}
		if value.ID != id || value.Side != tc.side || value.Hash != fmt.Sprintf("%x", sha256.Sum256(tc.body)) || value.Size != int64(len(tc.body)) {
			t.Fatal("wrong associated blob manifest")
		}
	}
}

func TestManagedBlobManifestRejectsMarkerSpoofAndInvalidScope(t *testing.T) {
	tr, _ := openTraffic(t)
	spoof := []byte("\n…[truncated] @blob sha256:" + fmt.Sprintf("%064d", 0) + " (len=999)")
	tr.record(newFlow("fixture.invalid", "GET", "/", nil, spoof))
	id := onlyExchangeID(t, tr)
	for _, tc := range []struct{ id, side string }{{id, "response"}, {id, "request"}, {id, "Response"}, {id, "../response"}, {"", "response"}, {"missing", "response"}} {
		if _, err := tr.BlobManifest(tc.id, tc.side); err == nil {
			t.Fatal("invalid or inline manifest accepted")
		}
	}
}

func TestManagedBlobManifestMissingFileWrongLengthAndClosedDB(t *testing.T) {
	for mode := 0; mode < 3; mode++ {
		t.Run(fmt.Sprint(mode), func(t *testing.T) {
			tr, dir := openTraffic(t)
			body := bytes.Repeat([]byte("body"), maxInlineBody)
			tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
			id := onlyExchangeID(t, tr)
			value, err := tr.BlobManifest(id, "response")
			if err != nil {
				t.Fatal(err)
			}
			if mode == 0 {
				if err := os.Remove(filepath.Join(dir, "_blobs", "sha256", value.Hash[:2], value.Hash+".bin")); err != nil {
					t.Fatal(err)
				}
			} else if mode == 1 {
				if _, err := tr.DB().Exec("UPDATE exchanges SET resp_len=resp_len+1 WHERE id=?", id); err != nil {
					t.Fatal(err)
				}
			} else {
				if err := tr.DB().Close(); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := tr.BlobManifest(id, "response"); err == nil {
				t.Fatal("unavailable metadata accepted")
			}
		})
	}
}

func TestManagedBlobManifestRejectsFIFOWithinDeadline(t *testing.T) {
	if os.Getenv("ARTEX_BLOB_FIFO_CHILD") == "1" {
		tr, dir := openTraffic(t)
		body := bytes.Repeat([]byte("body"), maxInlineBody)
		tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
		id := onlyExchangeID(t, tr)
		value, err := tr.BlobManifest(id, "response")
		if err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(dir, "_blobs", "sha256", value.Hash[:2], value.Hash+".bin")
		if err := os.Remove(path); err != nil {
			t.Fatal(err)
		}
		if err := syscall.Mkfifo(path, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := tr.BlobManifest(id, "response"); err == nil {
			t.Fatal("FIFO accepted")
		}
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestManagedBlobManifestRejectsFIFOWithinDeadline$")
	cmd.Env = append(os.Environ(), "ARTEX_BLOB_FIFO_CHILD=1")
	output, err := cmd.CombinedOutput()
	if ctx.Err() != nil {
		t.Fatal("metadata lookup blocked on FIFO")
	}
	if err != nil {
		t.Fatalf("FIFO child failed: %s", output)
	}
}

func TestManagedBlobManifestRejectsSymlinkAndDirectory(t *testing.T) {
	for _, kind := range []string{"symlink", "directory"} {
		t.Run(kind, func(t *testing.T) {
			tr, dir := openTraffic(t)
			body := bytes.Repeat([]byte("body"), maxInlineBody)
			tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
			id := onlyExchangeID(t, tr)
			value, err := tr.BlobManifest(id, "response")
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "_blobs", "sha256", value.Hash[:2], value.Hash+".bin")
			if err := os.Remove(path); err != nil {
				t.Fatal(err)
			}
			if kind == "symlink" {
				target := filepath.Join(dir, "outside.bin")
				if err := os.WriteFile(target, body, 0600); err != nil {
					t.Fatal(err)
				}
				if err := os.Symlink(target, path); err != nil {
					t.Fatal(err)
				}
			} else {
				if err := os.Mkdir(path, 0700); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := tr.BlobManifest(id, "response"); err == nil {
				t.Fatal("nonregular or symlink accepted")
			}
		})
	}
}

func TestManagedBlobManifestLiteralIdentityAndLegacyLayout(t *testing.T) {
	tr, dir := openTraffic(t)
	body := bytes.Repeat([]byte("body"), maxInlineBody)
	tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
	old := onlyExchangeID(t, tr)
	id := " \ufeffe\u0301 中文 한국어 "
	for _, table := range []string{"exchanges", "exchange_bodies"} {
		if _, err := tr.DB().Exec("UPDATE "+table+" SET id=? WHERE id=?", id, old); err != nil {
			t.Fatal(err)
		}
	}
	value, err := tr.BlobManifest(id, "response")
	if err != nil || value.ID != id {
		t.Fatal("literal identity not preserved", err)
	}
	if _, err := tr.BlobManifest(strings.Replace(id, "e\u0301", "é", 1), "response"); err == nil {
		t.Fatal("normalized identity accepted")
	}
	path := filepath.Join(dir, "_blobs", "sha256", value.Hash[:2], value.Hash+".bin")
	legacyDir := filepath.Join(filepath.Dir(path), value.Hash[2:4])
	if err := os.Mkdir(legacyDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(path, filepath.Join(legacyDir, value.Hash+".bin")); err != nil {
		t.Fatal(err)
	}
	legacy, err := tr.BlobManifest(id, "response")
	if err != nil || legacy != value {
		t.Fatal("legacy layout unavailable", err)
	}
}

func TestManagedBlobManifestRejectsCorruptMetadataAndLinkedDirectory(t *testing.T) {
	for mode := 0; mode < 6; mode++ {
		t.Run(fmt.Sprint(mode), func(t *testing.T) {
			tr, dir := openTraffic(t)
			body := bytes.Repeat([]byte("body"), maxInlineBody)
			tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
			id := onlyExchangeID(t, tr)
			var err error
			switch mode {
			case 0:
				_, err = tr.DB().Exec("UPDATE exchange_bodies SET resp_blob=? WHERE id=?", strings.Repeat("A", 64), id)
			case 1:
				_, err = tr.DB().Exec("UPDATE exchange_bodies SET resp_blob=NULL WHERE id=?", id)
			case 2:
				_, err = tr.DB().Exec("UPDATE exchanges SET resp_len=-1 WHERE id=?", id)
			case 3:
				_, err = tr.DB().Exec("UPDATE exchanges SET resp_len=NULL WHERE id=?", id)
			case 4:
				_, err = tr.DB().Exec("DELETE FROM exchanges WHERE id=?", id)
			case 5:
				from := filepath.Join(dir, "_blobs")
				to := filepath.Join(dir, "relocated")
				if err = os.Rename(from, to); err == nil {
					err = os.Symlink(to, from)
				}
			}
			if err != nil {
				t.Fatal(err)
			}
			if _, err := tr.BlobManifest(id, "response"); err == nil {
				t.Fatal("corrupt or linked metadata accepted")
			}
		})
	}
}

func TestManagedBlobLegacyHashNormalization(t *testing.T) {
	tr, _ := openTraffic(t)
	body := bytes.Repeat([]byte("body"), maxInlineBody)
	tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
	value, err := tr.BlobManifest(onlyExchangeID(t, tr), "response")
	if err != nil {
		t.Fatal(err)
	}
	file, size, err := tr.Blob(" " + strings.ToUpper(value.Hash) + "\t")
	if err != nil {
		t.Fatal("legacy hash input rejected", err)
	}
	defer file.Close()
	if size != int64(len(body)) {
		t.Fatal("legacy hash size changed")
	}
}
