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
func ServiceAuthMiddleware(expectedServiceKey string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		provided := r.Header.Get(ServiceAuthHeader)
		if !IsServiceAuthorized(expectedServiceKey, provided) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}
