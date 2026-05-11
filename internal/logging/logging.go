package logging

import (
	"log/slog"
	"os"
)

// #R001: Emit JSON structured logs to stdout at info level.
func NewLogger() *slog.Logger {
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})
	return slog.New(handler)
}
