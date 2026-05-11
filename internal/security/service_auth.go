package security

import (
	"crypto/subtle"
	"net/http"
)

const ServiceAuthHeader = "X-Valve-Service-Key"

func IsServiceAuthorized(expected string, provided string) bool {
	if expected == "" || provided == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(expected), []byte(provided)) == 1
}

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
