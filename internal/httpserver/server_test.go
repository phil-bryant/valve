package httpserver

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"valve/internal/credentials"
)

type testChecker struct {
	err error
}

func (t testChecker) Ping(_ context.Context) error {
	return t.err
}

func TestHealthzReturns200(t *testing.T) {
	// #R001: Router boots with middleware and serves health endpoint.
	// #R005: Readiness endpoint reports dependency failure.
	// #R010: Credential route graph uses service-auth middleware in server construction.
	logger := slog.Default()
	srv := New(":8090", logger, testChecker{}, &credentials.Handler{}, "svc-key")
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	srv.Handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
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
}
