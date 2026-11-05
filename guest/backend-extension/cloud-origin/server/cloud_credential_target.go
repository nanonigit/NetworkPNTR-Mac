package server

import (
	"os"

	"github.com/Autumn-27/artex/agent"
	"github.com/Autumn-27/artex/db"
)

// savedLLMModelsBase mirrors the pinned completion client's effective base.
func savedLLMModelsBase(format, baseURL string) string {
	cfg := agent.ConfigFrom(format, "", baseURL, "", "")
	if cfg.BaseURL != "" {
		return cfg.BaseURL
	}
	envKey, fallback := "OPENAI_BASE_URL", "https://api.openai.com/v1"
	if cfg.Provider() == "anthropic" {
		envKey, fallback = "ANTHROPIC_BASE_URL", "https://api.anthropic.com"
	}
	if override := os.Getenv(envKey); override != "" {
		return override
	}
	return fallback
}

func (s *Server) savedLLMProbeProfile(id int64, target db.LLMCredentialTarget) *db.LLMProfile {
	if s.m == nil || s.m.pg == nil {
		return nil
	}
	profile, err := s.m.pg.ProfileByID(id)
	if err != nil || profile == nil || !target.Matches(profile.CredentialTarget()) {
		return nil
	}
	return profile
}

func (s *Server) globalLLMKeyFor(cfg agent.Config) string {
	s.cfgMu.Lock()
	defer s.cfgMu.Unlock()
	target := db.LLMCredentialTarget{Format: cfg.Provider(), BaseURL: cfg.BaseURL, Proxy: cfg.Proxy}
	current := db.LLMCredentialTarget{Format: s.llmCfg.Provider(), BaseURL: s.llmCfg.BaseURL, Proxy: s.llmCfg.Proxy}
	if target.Matches(current) {
		return s.llmCfg.APIKey
	}
	return ""
}
