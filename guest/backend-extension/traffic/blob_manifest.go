package traffic

import (
	"database/sql"
	"errors"
	"os"
	"syscall"
	"unicode/utf8"
)

// ErrBlobMetadataUnavailable means the requested original body is not available.
var ErrBlobMetadataUnavailable = errors.New("original blob metadata unavailable")

// ErrBlobMetadataRead preserves storage failure separately from an absent body.
var ErrBlobMetadataRead = errors.New("original blob metadata read unavailable")

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
	unavailable := ErrBlobMetadataUnavailable
	if t == nil || t.db == nil {
		return BlobManifest{}, ErrBlobMetadataRead
	}
	if len(id) == 0 || len(id) > 8192 || !utf8.ValidString(id) {
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
	if err := t.db.QueryRow(query, id).Scan(&hash, &size); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return BlobManifest{}, unavailable
		}
		return BlobManifest{}, ErrBlobMetadataRead
	}
	if !hash.Valid || !blobHashRe.MatchString(hash.String) || size < 0 {
		return BlobManifest{}, unavailable
	}
	file, actualSize, err := t.openManagedBlob(hash.String)
	if err != nil {
		return BlobManifest{}, unavailable
	}
	closeErr := file.Close()
	if closeErr != nil || size != actualSize {
		return BlobManifest{}, unavailable
	}
	return BlobManifest{ID: id, Side: side, Hash: hash.String, Size: size}, nil
}

// openManagedBlob anchors every path component and never follows a symlink or
// waits for a FIFO peer. Callers own the returned regular-file handle.
func (t *Traffic) openManagedBlob(hash string) (*os.File, int64, error) {
	unavailable := errors.New("original blob unavailable")
	if t == nil || !blobHashRe.MatchString(hash) {
		return nil, 0, unavailable
	}
	flags := syscall.O_RDONLY | syscall.O_CLOEXEC | syscall.O_NOFOLLOW | syscall.O_NONBLOCK
	root, err := syscall.Open(t.dir, flags|syscall.O_DIRECTORY, 0)
	if err != nil {
		return nil, 0, unavailable
	}
	defer syscall.Close(root)
	layouts := [][]string{
		{"_blobs", "sha256", hash[:2], hash + ".bin"},
		{"_blobs", "sha256", hash[:2], hash[2:4], hash + ".bin"},
	}
	for _, parts := range layouts {
		fd := root
		missing := false
		for index, part := range parts {
			options := flags
			if index != len(parts)-1 {
				options |= syscall.O_DIRECTORY
			}
			next, openErr := syscall.Openat(fd, part, options, 0)
			if fd != root {
				syscall.Close(fd)
			}
			if openErr != nil {
				if openErr != syscall.ENOENT {
					return nil, 0, unavailable
				}
				missing = true
				break
			}
			fd = next
		}
		if missing {
			continue
		}
		file := os.NewFile(uintptr(fd), "original blob")
		if file == nil {
			syscall.Close(fd)
			return nil, 0, unavailable
		}
		info, statErr := file.Stat()
		if statErr != nil || !info.Mode().IsRegular() {
			file.Close()
			return nil, 0, unavailable
		}
		return file, info.Size(), nil
	}
	return nil, 0, unavailable
}
