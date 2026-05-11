package main

import (
	"log/slog"
	"strings"
	"testing"
)

func TestRunFailsFastWhenDatabaseURLMissing(t *testing.T) {
	// #R001: Main entrypoint surfaces run failures with explicit non-success path.
	// #R005: Run fails before service start when config requirements are unmet.
	// #R010: Lifecycle exits deterministically on startup failure path.
	t.Setenv("VALVE_DATABASE_URL", "")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "https://ingest.example.com/v1/events/batch")
	err := run(slog.Default())
	if err == nil || !strings.Contains(err.Error(), "VALVE_DATABASE_URL is required") {
		t.Fatalf("expected config validation failure for missing db url, got %v", err)
	}
}

func TestRunFailsFastWhenUploadEndpointMissing(t *testing.T) {
	t.Setenv("VALVE_DATABASE_URL", "postgres://localhost:5432/valve?sslmode=disable")
	t.Setenv("VALVE_UPLOAD_ENDPOINT", "")
	err := run(slog.Default())
	if err == nil || !strings.Contains(err.Error(), "VALVE_UPLOAD_ENDPOINT is required") {
		t.Fatalf("expected config validation failure for missing upload endpoint, got %v", err)
	}
}
