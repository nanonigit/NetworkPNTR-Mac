package traffic

import (
	"database/sql"
	"errors"
	"unicode/utf8"
)

// BlobManifest identifies a stored oversized body associated with one exact exchange side.
// It does not interpret marker strings or claim provenance of remote response content.
type BlobManifest struct {
	ID   string `json:"id"`
	Side string `json:"side"`
	Hash string `json:"hash"`
	Size int64  `json:"size"`
}

// BlobManifest reads structural association metadata, never the rendered HTTP text.
func (t *Traffic) BlobManifest(id, side string) (BlobManifest, error) {
	unavailable := errors.New("original blob metadata unavailable")
	if t == nil || t.db == nil || len(id) == 0 || len(id) > 8192 || !utf8.ValidString(id) {
		return BlobManifest{}, unavailable
	}
	for _, r := range id {
		if r < 32 || r == 127 {
			return BlobManifest{}, unavailable
		}
	}
	var query string
	switch side {
	case "request":
		query = `SELECT b.req_blob,e.req_len FROM exchange_bodies b JOIN exchanges e ON e.id=b.id WHERE b.id=?`
	case "response":
		query = `SELECT b.resp_blob,e.resp_len FROM exchange_bodies b JOIN exchanges e ON e.id=b.id WHERE b.id=?`
	default:
		return BlobManifest{}, unavailable
	}
	var hash sql.NullString
	var size int64
	if err := t.db.QueryRow(query, id).Scan(&hash, &size); err != nil || !hash.Valid || !blobHashRe.MatchString(hash.String) || size < 0 {
		return BlobManifest{}, unavailable
	}
	file, actualSize, err := t.Blob(hash.String)
	if err != nil {
		return BlobManifest{}, unavailable
	}
	closeErr := file.Close()
	if closeErr != nil || size != actualSize {
		return BlobManifest{}, unavailable
	}
	return BlobManifest{ID: id, Side: side, Hash: hash.String, Size: size}, nil
}
