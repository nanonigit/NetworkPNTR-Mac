package agent

import (
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

type llmRedirectOrigin struct {
	scheme   string
	hostname string
	port     int
}

// LLMRedirectTransport keeps redirect bodies out of provider errors and wire
// captures. A malformed Location would otherwise appear in net/http's error.
type LLMRedirectTransport struct {
	http.RoundTripper
}

func (t LLMRedirectTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	response, err := t.RoundTripper.RoundTrip(request)
	if err != nil || response == nil || response.StatusCode < 300 || response.StatusCode >= 400 {
		return response, err
	}
	if response.Body != nil {
		_ = response.Body.Close()
	}
	response.Body = http.NoBody
	response.ContentLength = 0
	response.Header.Del("Content-Length")
	if _, err := request.URL.Parse(response.Header.Get("Location")); err != nil {
		response.Header.Del("Location")
	}
	return response, nil
}

func llmRequestOrigin(request *http.Request) (llmRedirectOrigin, bool) {
	if request == nil || request.URL == nil {
		return llmRedirectOrigin{}, false
	}
	origin, ok := parseLLMRedirectOrigin(request.URL)
	if !ok || request.Host == "" {
		return origin, ok
	}
	// An explicit Host override must describe the same authority as the URL.
	authority, valid := parseLLMRedirectOrigin(&url.URL{Scheme: request.URL.Scheme, Host: request.Host})
	return origin, valid && origin == authority
}

func parseLLMRedirectOrigin(target *url.URL) (llmRedirectOrigin, bool) {
	host := target.Hostname()
	if host == "" || target.User != nil || target.Opaque != "" {
		return llmRedirectOrigin{}, false
	}
	var port int
	switch target.Scheme {
	case "https":
		port = 443
	case "http":
		port = 80
	default:
		return llmRedirectOrigin{}, false
	}
	if explicit := target.Port(); explicit != "" {
		number, err := strconv.Atoi(explicit)
		if err != nil || number < 1 || number > 65535 {
			return llmRedirectOrigin{}, false
		}
		port = number
	}
	// Fold ASCII DNS names and ordinary IP literals. Keep Unicode names and
	// IPv6 interface zones literal rather than guessing equivalent authorities.
	if strings.IndexFunc(host, func(r rune) bool { return r > 127 || r == '%' }) == -1 {
		host = strings.ToLower(host)
	}
	return llmRedirectOrigin{scheme: target.Scheme, hostname: host, port: port}, true
}

// CheckLLMRedirect keeps credentials and request bodies on their initial HTTP
// origin. Retain the standard client's redirect hop bound.
func CheckLLMRedirect(request *http.Request, via []*http.Request) error {
	if len(via) > 0 && len(via) < 10 {
		origin, originValid := llmRequestOrigin(via[0])
		target, targetValid := llmRequestOrigin(request)
		if originValid && targetValid && origin == target {
			return nil
		}
	}
	if request != nil && request.Response != nil {
		request.Response.Header.Del("Location")
	}
	return http.ErrUseLastResponse
}
