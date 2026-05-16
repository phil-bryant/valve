package httpserver

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"valve/internal/credentials"
)

type testChecker struct {
	err error
}

func (t testChecker) Ping(_ context.Context) error {
	return t.err
}

func TestHealthzReturns200AndJSONContract(t *testing.T) {
	// #R001: Router boots with middleware and serves health endpoint.
	// #R005: Health probe response matches the OpenAPI application/json
	// contract used by DAST Schemathesis preflight.
	// #R010: Credential route graph uses service-auth middleware in server construction.
	logger := slog.Default()
	srv := New(":8090", logger, testChecker{}, &credentials.Handler{}, "svc-key")
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	srv.Handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
		t.Fatalf("expected application/json content type, got %q", got)
	}
	var body struct {
		OK bool `json:"ok"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("response body is not valid JSON: %v (body=%q)", err, rec.Body.String())
	}
	if !body.OK {
		t.Fatalf("expected ok=true, got %+v", body)
	}
}

func TestReadyzFailsWhenDatabaseUnavailable(t *testing.T) {
	logger := slog.Default()
	srv := New(":8090", logger, testChecker{err: errors.New("db down")}, &credentials.Handler{}, "svc-key")
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	srv.Handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
		t.Fatalf("expected application/json content type, got %q", got)
	}
}

func TestSecureResponseHeadersAreSetOnEveryRoute(t *testing.T) {
	// #R015: Every response carries baseline security headers so DAST scans
	// (and real clients) do not need to rely on browser MIME-sniffing or
	// framing defaults.
	logger := slog.Default()
	srv := New(":8090", logger, testChecker{}, &credentials.Handler{}, "svc-key")
	for _, path := range []string{"/healthz", "/readyz", "/v1/piston/upload-target"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		srv.Handler.ServeHTTP(rec, req)
		if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
			t.Fatalf("%s: expected X-Content-Type-Options=nosniff, got %q", path, got)
		}
		if got := rec.Header().Get("X-Frame-Options"); got != "DENY" {
			t.Fatalf("%s: expected X-Frame-Options=DENY, got %q", path, got)
		}
		if got := rec.Header().Get("Referrer-Policy"); got != "no-referrer" {
			t.Fatalf("%s: expected Referrer-Policy=no-referrer, got %q", path, got)
		}
	}
}

func TestUploadTargetRouteRequiresServiceAuth(t *testing.T) {
	logger := slog.Default()
	srv := New(":8090", logger, testChecker{}, &credentials.Handler{}, "svc-key")
	req := httptest.NewRequest(http.MethodPost, "/v1/piston/upload-target", nil)
	rec := httptest.NewRecorder()

	srv.Handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
		t.Fatalf("expected application/json content type, got %q", got)
	}
	var body struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("401 body is not valid JSON: %v (body=%q)", err, rec.Body.String())
	}
	if body.Error == "" {
		t.Fatalf("expected non-empty error field in 401 body, got %+v", body)
	}
}
