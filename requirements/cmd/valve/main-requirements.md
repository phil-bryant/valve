# Main Entrypoint Requirements

## Scope

Applies to `cmd/valve/main.go`.

R001  Statement: The main entrypoint must initialize a structured logger and exit non-zero when the server lifecycle returns an error.
Design: `main` calls `logging.NewLogger`, passes the logger to `run`, and on a non-nil error calls `logger.Error` then `os.Exit(1)`. A nil return from `run` exits with code 0.
Tests:
- R001-T01: Verify that `main` exits with code 1 when `run` returns an error (via subprocess or mock).
- R001-T02: Verify that `main` exits with code 0 when `run` returns nil.

R005  Statement: The run function must load configuration, initialize storage, apply the schema, configure upload target discovery, and wire all service dependencies before accepting traffic.
Design: `run` calls `config.Load`, creates a `PostgresStore`, calls `ApplySchemaFromFile`, constructs a `DevAuthorizer`, creates a `Service`, calls `ConfigureUploadTargetDiscovery` (deriving the allowed hosts from `VALVE_UPLOAD_ENDPOINT` when `VALVE_UPLOAD_TARGET_ALLOWED_HOSTS` is empty), constructs a `Handler` and `http.Server`, then starts `ListenAndServe` in a goroutine. A config load failure, storage creation failure, schema application failure, or discovery configuration failure returns an error before any traffic is accepted.
Tests:
- R005-T01: Verify that `run` returns an error when `VALVE_DATABASE_URL` is unset.
- R005-T02: Verify that `run` returns an error when `VALVE_UPLOAD_ENDPOINT` is unset.
- R005-T03: Verify that `run` returns an error when `VALVE_UPLOAD_ENDPOINT` contains an invalid URL with no hostname.

R010  Statement: The server must shut down gracefully within a bounded timeout when it receives SIGINT, SIGTERM, or a server error.
Design: `run` waits on a signal channel (SIGINT, SIGTERM) and a server error channel. On either event it calls `server.Shutdown` with a 10-second context timeout. `http.ErrServerClosed` from `ListenAndServe` is not treated as an error.
Tests:
- R010-T01: Verify that sending SIGINT triggers `Shutdown` and `run` returns nil.
- R010-T02: Verify that a `ListenAndServe` error other than `http.ErrServerClosed` is returned from `run`.
- R010-T03: Verify that `http.ErrServerClosed` from `ListenAndServe` does not cause `run` to return an error.

## Changelog

- 2026-05-16: Numbered test bullets with R###-T## scheme.
- 2026-05-16: Rewrote with concrete startup-sequence and shutdown acceptance criteria.
- 2026-05-10: Added requirements coverage for backend source traceability.
