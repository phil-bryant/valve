package security

import (
	"crypto/subtle"
	"net/http"
)

const ServiceAuthHeader = "X-Valve-Service-Key"

// #R001: Authorize service keys with non-empty constant-time comparison.
func IsServiceAuthorized(expected string, provided string) bool {
	if expected == "" || provided == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(expected), []byte(provided)) == 1
}

// #R005: Reject unauthorized requests before invoking downstream handlers.
// The 401 body is JSON-encoded to match the OpenAPI ErrorResponse contract so
// DAST contract testing (Schemathesis) does not flag a documented response
// as having an undocumented content type.
func ServiceAuthMiddleware(expectedServiceKey string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		provided := r.Header.Get(ServiceAuthHeader)
		if !IsServiceAuthorized(expectedServiceKey, provided) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"unauthorized"}` + "\n"))
			return
		}
		next.ServeHTTP(w, r)
	})
}
