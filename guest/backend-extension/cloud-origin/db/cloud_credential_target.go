package db

import (
	"errors"
	"strings"
)

var ErrLLMCredentialTargetChanged = errors.New("Enter an API key when changing the connection target")

// LLMCredentialTarget is the connection configuration to which a key belongs.
type LLMCredentialTarget struct {
	Format  string
	BaseURL string
	Proxy   string
}

func (t LLMCredentialTarget) Matches(other LLMCredentialTarget) bool {
	return strings.TrimSpace(t.Format) == strings.TrimSpace(other.Format) &&
		strings.TrimRight(strings.TrimSpace(t.BaseURL), "/") == strings.TrimRight(strings.TrimSpace(other.BaseURL), "/") &&
		strings.TrimSpace(t.Proxy) == strings.TrimSpace(other.Proxy)
}

func (p *LLMProfile) CredentialTarget() LLMCredentialTarget {
	return LLMCredentialTarget{Format: p.Format, BaseURL: p.BaseURL, Proxy: p.Proxy}
}
