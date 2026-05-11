package config

import (
	"testing"
)

func TestLoadReturnsConfigFromEnvironment(t *testing.T) {
	// #R001: Load resolves env-backed config with defaults and explicit values.
	// #R005: Required env fields produce explicit errors when absent.
	// #R010: Boolean parsing falls back for invalid inputs.
	t.Setenv("VALVE_ADDR", ":18090")
	t.Setenv("VALVE_DATABASE_URL", "postgres://localhost:5432/valve?sslmode=disable")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "https://ingest.example.com/v1/events/batch")
	t.Setenv("VALVE_DEV_AUTH_ALLOW_ALL", "true")
	t.Setenv("VALVE_HMAC_MODE_ENABLED", "true")
	t.Setenv("VALVE_SERVICE_AUTH_KEY", "runtime-value-placeholder")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if cfg.Addr != ":18090" || cfg.DatabaseURL == "" || cfg.UploadEndpoint == "" {
		t.Fatalf("unexpected config basics: %+v", cfg)
	}
	if !cfg.DevAuthAllowAll || !cfg.HMACModeEnabled || cfg.ServiceAuthKey != "runtime-value-placeholder" { // pragma: allowlist secret
		t.Fatalf("unexpected config booleans/secrets: %+v", cfg)
	}
}

func TestLoadRequiresDatabaseURL(t *testing.T) {
	t.Setenv("VALVE_DATABASE_URL", "")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "https://ingest.example.com/v1/events/batch")
	_, err := Load()
	if err == nil || err.Error() != "VALVE_DATABASE_URL is required" {
		t.Fatalf("expected missing database url error, got %v", err)
	}
}

func TestLoadRequiresUploadEndpoint(t *testing.T) {
	t.Setenv("VALVE_DATABASE_URL", "postgres://localhost:5432/valve?sslmode=disable")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "")
	_, err := Load()
	if err == nil || err.Error() != "VALVE_UPLOAD_ENDPOINT is required" {
		t.Fatalf("expected missing upload endpoint error, got %v", err)
	}
}

func TestParseBoolOrDefaultFallsBackOnInvalidValue(t *testing.T) {
	t.Setenv("VALVE_DEV_AUTH_ALLOW_ALL", "definitely-not-bool")
	if !parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", true) {
		t.Fatalf("expected fallback true for invalid bool env")
	}
	if parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", false) {
		t.Fatalf("expected fallback false for invalid bool env")
	}
}
