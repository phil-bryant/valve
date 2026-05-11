#!/usr/bin/env bats

@test "README documents startup and env requirements" {
  run rg "VALVE_DATABASE_URL" README.md
  [ "$status" -eq 0 ]
  run rg "VALVE_UPLOAD_ENDPOINT" README.md
  [ "$status" -eq 0 ]
  run rg "go run ./cmd/valve" README.md
  [ "$status" -eq 0 ]
}

@test "README documents ingest curl and health endpoints" {
  run rg "POST /v1/valve/credentials/register" README.md
  [ "$status" -eq 0 ]
  run rg "curl -X POST" README.md
  [ "$status" -eq 0 ]
  run rg "/healthz" README.md
  [ "$status" -eq 0 ]
  run rg "/readyz" README.md
  [ "$status" -eq 0 ]
}

@test "README startup examples avoid hardcoded credential-like literals" {
  #R025
  run rg 'postgres://[^[:space:]]+:[^[:space:]]+@' README.md
  [ "$status" -eq 1 ]
  run rg 'dev-service-key|svc-key|secret-key|password123' README.md
  [ "$status" -eq 1 ]
}
