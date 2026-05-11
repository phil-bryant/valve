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

	// #R005: Expose health and readiness probes with dependency checks.
	router.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	router.Get("/readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := checker.Ping(ctx); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte("not ready"))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ready"))
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
