# Main Entrypoint Requirements

## Scope

Applies to `cmd/valve/main.go`.

R001  Statement: Initialize logger and run server lifecycle through run().
Design: Design: `main()` builds logger, invokes `run(logger)`, logs terminal error, and exits non-zero on failure.
Tests:
- Add/maintain targeted tests that validate r001 behavior.

R005  Statement: Load runtime configuration and initialize storage before serving traffic.
Design: Design: `run()` calls config load, creates postgres store, applies schema, and wires service dependencies before ListenAndServe.
Tests:
- Add/maintain targeted tests that validate r005 behavior.

R010  Statement: Support graceful shutdown for OS termination signals and server errors.
Design: Design: Wait on signal/error channels and perform bounded `Shutdown` with timeout context.
Tests:
- Add/maintain targeted tests that validate r010 behavior.

## Changelog

- 2026-05-10: Added requirements coverage for backend source traceability.
