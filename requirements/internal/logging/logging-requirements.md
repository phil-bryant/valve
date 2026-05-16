# Logging Requirements

## Scope

Applies to `internal/logging/logging.go`.

R001  Statement: The logger must emit JSON-structured output to stdout at info level.
Design: `NewLogger` returns a `*slog.Logger` backed by `slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})`. Debug-level messages must be suppressed. Info and above must be emitted.
Tests:
- R001-T01: Verify that `NewLogger` returns a non-nil logger.
- R001-T02: Verify that a message logged at `Info` level produces a JSON-parseable line on stdout.
- R001-T03: Verify that a message logged at `Debug` level is not emitted (suppressed by the info threshold).

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete output-format and level-filtering acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
