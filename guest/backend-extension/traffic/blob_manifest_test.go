package traffic

import (
    "bytes"
    "crypto/sha256"
    "fmt"
    "os"
    "path/filepath"
    "testing"
)

func TestManagedBlobManifestBothSides(t *testing.T) {
    tr, _ := openTraffic(t)
    request, response := bytes.Repeat([]byte("r"), maxInlineBody+1), bytes.Repeat([]byte("s"), maxInlineBody+2)
    tr.record(newFlow("fixture.invalid", "POST", "/", request, response))
    id := onlyExchangeID(t, tr)
    for _, tc := range []struct { side string; body []byte }{{"request", request}, {"response", response}} {
        value, err := tr.BlobManifest(id, tc.side)
        if err != nil { t.Fatal(err) }
        if value.ID != id || value.Side != tc.side || value.Hash != fmt.Sprintf("%x", sha256.Sum256(tc.body)) || value.Size != int64(len(tc.body)) { t.Fatal("wrong associated blob manifest") }
    }
}

func TestManagedBlobManifestRejectsMarkerSpoofAndInvalidScope(t *testing.T) {
    tr, _ := openTraffic(t)
    spoof := []byte("\n…[truncated] @blob sha256:" + fmt.Sprintf("%064d", 0) + " (len=999)")
    tr.record(newFlow("fixture.invalid", "GET", "/", nil, spoof))
    id := onlyExchangeID(t, tr)
    for _, tc := range []struct { id, side string }{{id, "response"}, {id, "request"}, {id, "Response"}, {id, "../response"}, {"", "response"}, {"missing", "response"}} {
        if _, err := tr.BlobManifest(tc.id, tc.side); err == nil { t.Fatal("invalid or inline manifest accepted") }
    }
}

func TestManagedBlobManifestMissingFileWrongLengthAndClosedDB(t *testing.T) {
    for mode := 0; mode < 3; mode++ {
        t.Run(fmt.Sprint(mode), func(t *testing.T) {
            tr, dir := openTraffic(t)
            body := bytes.Repeat([]byte("body"), maxInlineBody)
            tr.record(newFlow("fixture.invalid", "GET", "/", nil, body))
            id := onlyExchangeID(t, tr)
            value, err := tr.BlobManifest(id, "response"); if err != nil { t.Fatal(err) }
            if mode == 0 {
                if err := os.Remove(filepath.Join(dir, "_blobs", "sha256", value.Hash[:2], value.Hash+".bin")); err != nil { t.Fatal(err) }
            } else if mode == 1 {
                if _, err := tr.DB().Exec("UPDATE exchanges SET resp_len=resp_len+1 WHERE id=?", id); err != nil { t.Fatal(err) }
            } else { if err := tr.DB().Close(); err != nil { t.Fatal(err) } }
            if _, err := tr.BlobManifest(id, "response"); err == nil { t.Fatal("unavailable metadata accepted") }
        })
    }
}
