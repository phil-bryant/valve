package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"valve/internal/auth"
	"valve/internal/config"
	"valve/internal/credentials"
	"valve/internal/httpserver"
	"valve/internal/logging"
	"valve/internal/storage"
)

// #R001: Bootstrap logger and execute top-level run lifecycle.
func main() {
	logger := logging.NewLogger()
	if err := run(logger); err != nil {
		logger.Error("server exited with error", "error", err)
		os.Exit(1)
	}
}

// #R005: Build runtime dependencies before serving network traffic.
func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	ctx := context.Background()
	store, err := storage.NewPostgresStore(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer store.Close()

	schemaPath := filepath.Join("internal", "storage", "schema.sql")
	if err := store.ApplySchemaFromFile(ctx, schemaPath); err != nil {
		return err
	}

	authorizer := auth.DevAuthorizer{AllowAll: cfg.DevAuthAllowAll}
	service := credentials.NewService(store, authorizer, cfg.UploadEndpoint, cfg.HMACModeEnabled, cfg.DevAuthAllowAll)
	handler := credentials.NewHandler(service)
	server := httpserver.New(cfg.Addr, logger, store, handler, cfg.ServiceAuthKey)

	errCh := make(chan error, 1)
	go func() {
		logger.Info("starting valve server", "addr", cfg.Addr)
		if serveErr := server.ListenAndServe(); serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
			errCh <- serveErr
		}
		close(errCh)
	}()

	// #R010: Coordinate graceful shutdown from signal or server error paths.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-stop:
		logger.Info("shutdown signal received", "signal", sig.String())
	case serveErr := <-errCh:
		if serveErr != nil {
			return serveErr
		}
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return server.Shutdown(shutdownCtx)
}
