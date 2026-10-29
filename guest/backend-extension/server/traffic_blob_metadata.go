package server

import (
	"errors"
	"net/http"
	"net/url"
	"unicode/utf8"

	"github.com/Autumn-27/artex/traffic"
)

// getTrafficBlobMetadata is registered within the existing authenticated API mux.
func (s *Server) getTrafficBlobMetadata(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeErr(w, http.StatusMethodNotAllowed, "method unavailable")
		return
	}
	if len(r.URL.RawQuery) > 32768 {
		writeErr(w, http.StatusBadRequest, "invalid blob scope")
		return
	}
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil || len(query) != 2 || len(query["id"]) != 1 || len(query["side"]) != 1 {
		writeErr(w, http.StatusBadRequest, "invalid blob scope")
		return
	}
	id, side := query.Get("id"), query.Get("side")
	valid := len(id) > 0 && len(id) <= 8192 && utf8.ValidString(id) && (side == "request" || side == "response")
	for _, code := range id {
		if code < 32 || code == 127 {
			valid = false
		}
	}
	if !valid {
		writeErr(w, http.StatusBadRequest, "invalid blob scope")
		return
	}
	if s.m == nil || s.m.Traffic() == nil {
		writeErr(w, http.StatusNotFound, "original blob unavailable")
		return
	}
	value, err := s.m.Traffic().BlobManifest(id, side)
	if err != nil {
		if errors.Is(err, traffic.ErrBlobMetadataRead) {
			writeErr(w, http.StatusServiceUnavailable, "traffic storage unavailable")
		} else {
			writeErr(w, http.StatusNotFound, "original blob unavailable")
		}
		return
	}
	writeJSON(w, http.StatusOK, value)
}
