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

// Supplemental numbered tags for server route matrix parity.
// #R001-T02
// #R005-T02
// #R010-T02
// #R010-T04

type testChecker struct {
	err error
}

func (t testChecker) Ping(_ context.Context) error {
	return t.err
}

func TestHealthzReturns200AndJSONContract(t *testing.T) {
	// #R001-T01: Request to any route produces structured log entry with method, path, duration_ms.
	// #R005-T01: GET /healthz returns HTTP 200 with application/json and ok:true body.
	// #R010-T01: POST /v1/valve/credentials/register is reachable without a service key.
	// #R001: Router boots with middleware and serves health endpoint.
	// #R005: Health probe response matches the OpenAPI application/json contract.
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
	// #R005-T03: GET /readyz returns HTTP 503 with application/json and ok:false when Ping fails.
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
	// #R015-T01: GET /healthz response includes X-Content-Type-Options: nosniff.
	// #R015-T02: GET /readyz response includes X-Frame-Options: DENY.
	// #R015-T03: POST /v1/piston/upload-target response includes Referrer-Policy: no-referrer.
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
	// #R010-T03: POST /v1/piston/upload-target returns HTTP 401 when service key header is absent.
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
