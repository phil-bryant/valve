package httpserver

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"valve/internal/credentials"
	"valve/internal/security"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type ReadinessChecker interface {
	Ping(ctx context.Context) error
}

// #R001: Build router with baseline middleware and structured request logging.
func New(addr string, logger *slog.Logger, checker ReadinessChecker, handler *credentials.Handler, serviceAuthKey string) *http.Server {
	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.RealIP)
	router.Use(middleware.Recoverer)
	router.Use(requestLogMiddleware(logger))
	// #R015: Apply baseline security response headers on every route so DAST
	// scanners (and real clients) do not have to rely on browser-side
	// MIME-sniffing or framing defaults.
	router.Use(secureResponseHeadersMiddleware)

	// #R005: Expose health and readiness probes with JSON bodies so the
	// responses match the OpenAPI contract and DAST contract testing
	// (Schemathesis) accepts the documented application/json content type.
	router.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}` + "\n"))
	})
	router.Get("/readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		w.Header().Set("Content-Type", "application/json")
		if err := checker.Ping(ctx); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"ok":false,"reason":"dependency_unavailable"}` + "\n"))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}` + "\n"))
	})

	// #R010: Route credential APIs and secure verification with service authentication.
	router.Route("/v1/valve/credentials", func(r chi.Router) {
		r.Post("/register", handler.RegisterCredential)
		r.Post("/revoke", handler.RevokeCredential)
		r.Post("/rotate", handler.RotateCredential)
		r.Get("/", handler.ListCredentials)
		r.With(func(next http.Handler) http.Handler {
			return security.ServiceAuthMiddleware(serviceAuthKey, next)
		}).Get("/{credential_id}/verification", handler.VerificationLookup)
	})
	router.With(func(next http.Handler) http.Handler {
		return security.ServiceAuthMiddleware(serviceAuthKey, next)
	}).Post("/v1/piston/upload-target", handler.UploadTarget)

	// #R020: Return RFC 9110-compliant 405 responses so contract testers (e.g.
	// Schemathesis unsupported_method checks) see an Allow header on unknown verbs.
	router.MethodNotAllowed(methodNotAllowedHandler)

	return &http.Server{
		Addr:         addr,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
}

func requestLogMiddleware(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			next.ServeHTTP(w, r)
			logger.Info("http_request",
				"method", r.Method,
				"path", r.URL.Path,
				"duration_ms", time.Since(start).Milliseconds(),
			)
		})
	}
}

// #R015: Apply a small set of baseline security headers to every response so
// API consumers (and DAST scanners) cannot fall back on MIME-sniffing or
// framing behaviours that valve does not intend to support. Headers are set
// before the downstream handler runs so any handler-supplied values for the
// same names still take precedence on explicit overwrite.
func methodNotAllowedHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Allow", "GET, HEAD, OPTIONS, POST")
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusMethodNotAllowed)
	_, _ = w.Write([]byte(`{"error":"method not allowed"}` + "\n"))
}

func secureResponseHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}
