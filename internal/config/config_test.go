package config

import (
	"testing"
)

func TestLoadReturnsConfigFromEnvironment(t *testing.T) {
	// #R001-T01: When VALVE_ADDR is unset, Addr is :8090 (default).
	// #R001-T02: When VALVE_ADDR is set, Addr reflects that value.
	// #R005-T05: Load succeeds when all required variables are set.
	// #R010-T02: "true" parses to true.
	// #R015-T02: Tenant routes string produces map with two entries.
	// #R001: Load resolves env-backed config with defaults and explicit values.
	// #R005: Required env fields produce explicit errors when absent.
	// #R010: Boolean parsing falls back for invalid inputs.
	t.Setenv("VALVE_ADDR", ":18090")
	t.Setenv("VALVE_DATABASE_URL", "postgres://localhost:5432/valve?sslmode=disable")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "https://ingest.example.com/v1/events/batch")
	t.Setenv("VALVE_DEV_AUTH_ALLOW_ALL", "true")
	t.Setenv("VALVE_HMAC_MODE_ENABLED", "true")
	t.Setenv("VALVE_SERVICE_AUTH_KEY", "runtime-value-placeholder")
	t.Setenv("VALVE_UPLOAD_TARGET_TTL_SECONDS", "600")
	t.Setenv("VALVE_UPLOAD_TARGET_ROUTING_VERSION", "routes-2026-05-11")
	t.Setenv("VALVE_UPLOAD_TARGET_ALLOWED_HOSTS", "ingest.example.com,ingest-alt.example.com")
	t.Setenv("VALVE_UPLOAD_TARGET_TENANT_ROUTES", "tenant_a=https://ingest-alt.example.com/v1/events/batch")
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
	if cfg.UploadTargetTTLSeconds != 600 || cfg.UploadTargetRoutingVersion != "routes-2026-05-11" {
		t.Fatalf("unexpected upload target discovery defaults: %+v", cfg)
	}
	if len(cfg.UploadTargetAllowedHosts) != 2 || cfg.UploadTargetAllowedHosts[0] != "ingest.example.com" {
		t.Fatalf("unexpected upload target host allowlist: %+v", cfg.UploadTargetAllowedHosts)
	}
	if cfg.UploadTargetTenantRoutes["tenant_a"] == "" {
		t.Fatalf("expected parsed tenant upload target route")
	}
}

func TestLoadRequiresDatabaseURL(t *testing.T) {
	// #R005-T01: Load returns error when VALVE_DATABASE_URL is unset.
	t.Setenv("VALVE_DATABASE_URL", "")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "https://ingest.example.com/v1/events/batch")
	_, err := Load()
	if err == nil || err.Error() != "VALVE_DATABASE_URL is required" {
		t.Fatalf("expected missing database url error, got %v", err)
	}
}

func TestLoadRequiresUploadEndpoint(t *testing.T) {
	// #R005-T02: Load returns error when VALVE_UPLOAD_ENDPOINT is unset.
	t.Setenv("VALVE_DATABASE_URL", "postgres://localhost:5432/valve?sslmode=disable")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "")
	_, err := Load()
	if err == nil || err.Error() != "VALVE_UPLOAD_ENDPOINT is required" {
		t.Fatalf("expected missing upload endpoint error, got %v", err)
	}
}

func TestParseBoolOrDefaultFallsBackOnInvalidValue(t *testing.T) {
	// #R010-T04: Invalid value returns fallback rather than error.
	t.Setenv("VALVE_DEV_AUTH_ALLOW_ALL", "definitely-not-bool")
	if !parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", true) {
		t.Fatalf("expected fallback true for invalid bool env")
	}
	if parseBoolOrDefault("VALVE_DEV_AUTH_ALLOW_ALL", false) {
		t.Fatalf("expected fallback false for invalid bool env")
	}
}

func TestLoadRejectsNonPositiveUploadTargetTTL(t *testing.T) {
	// #R005-T03: Load returns error when VALVE_UPLOAD_TARGET_TTL_SECONDS is 0.
	t.Setenv("VALVE_DATABASE_URL", "postgres://localhost:5432/valve?sslmode=disable")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "https://ingest.example.com/v1/events/batch")
	t.Setenv("VALVE_UPLOAD_TARGET_TTL_SECONDS", "0")
	_, err := Load()
	if err == nil || err.Error() != "VALVE_UPLOAD_TARGET_TTL_SECONDS must be > 0" {
		t.Fatalf("expected non-positive ttl error, got %v", err)
	}
}
