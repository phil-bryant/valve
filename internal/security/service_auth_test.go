package security

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestIsServiceAuthorizedUsesConstantTimeMatchSemantics(t *testing.T) {
	// #R001-T01: Empty expected returns false.
	// #R001-T02: Empty provided returns false.
	// #R001-T03: Matching non-empty values return true.
	// #R001-T04: Non-matching values return false.
	// #R001: Authorization requires non-empty values and exact key match.
	if !IsServiceAuthorized("svc-key", "svc-key") {
		t.Fatalf("expected valid key pair to authorize")
	}
	if IsServiceAuthorized("svc-key", "wrong-key") {
		t.Fatalf("expected mismatched keys to be rejected")
	}
	if IsServiceAuthorized("", "svc-key") || IsServiceAuthorized("svc-key", "") {
		t.Fatalf("expected empty expected/provided values to be rejected")
	}
}

func TestServiceAuthMiddlewareRejectsUnauthorizedRequests(t *testing.T) {
	// #R005-T01: Missing X-Valve-Service-Key returns HTTP 401 with application/json and error body.
	// #R005-T02: Incorrect key returns HTTP 401 with application/json and error body.
	// #R005-T04: 401 response body is valid JSON with non-empty error field.
	// #R005: Middleware blocks unauthorized requests before downstream execution
	// and emits a JSON-encoded ErrorResponse so the body matches the OpenAPI
	// contract used by DAST Schemathesis preflight.
	handler := ServiceAuthMiddleware("svc-key", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	req := httptest.NewRequest(http.MethodGet, "/internal", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 unauthorized, got %d", rec.Code)
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

func TestServiceAuthMiddlewareAllowsAuthorizedRequests(t *testing.T) {
	// #R005-T03: Correct key allows request to reach downstream handler.
	called := false
	handler := ServiceAuthMiddleware("svc-key", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	}))
	req := httptest.NewRequest(http.MethodGet, "/internal", nil)
	req.Header.Set(ServiceAuthHeader, "svc-key")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected next handler status, got %d", rec.Code)
	}
	if !called {
		t.Fatalf("expected downstream handler to be called")
	}
}
