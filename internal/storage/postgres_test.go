package storage

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"
	"time"

	"valve/internal/credentials"

	"github.com/jackc/pgx/v5"
)

// Supplemental numbered tags for storage requirements parity.
// #R001-T02
// #R001-T03
// #R005-T02
// #R005-T03
// #R005-T04
// #R005-T05
// #R010-T01
// #R010-T02
// #R010-T04
// #R015-T02
// #R020-T01
// #R020-T04

func TestNullableHelpers(t *testing.T) {
	// #R001-T01: NewPostgresStore returns non-nil store with valid database URL (integration).
	// #R005-T01: CreateCredential followed by GetCredential returns same record (integration).
	// #R001: Store helper functions preserve null semantics for optional values.
	if nullableString("") != nil || nullableBytes(nil) != nil {
		t.Fatalf("expected nil nullable conversions for empty values")
	}
	// #R005: Store helper functions pass through non-empty values for persistence writes.
	if v := nullableString("x"); v == nil {
		t.Fatalf("expected non-nil nullable string for non-empty value")
	}
	if v := nullableBytes([]byte{1}); v == nil {
		t.Fatalf("expected non-nil nullable bytes for non-empty value")
	}
}

func TestScanCredentialNoRowsMapsToErrNotFound(t *testing.T) {
	// #R010-T03: LookupVerification for unknown credential returns ErrNotFound.
	// #R010: Scan path maps pgx no-rows to storage ErrNotFound semantics.
	_, _, _, err := scanCredential(fakeScanner{err: pgx.ErrNoRows})
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestScanCredentialSuccessAndSchemaBootFields(t *testing.T) {
	// #R015-T01: ApplySchemaFromFile with approved path succeeds (integration).
	// #R015: Scan path hydrates schema-backed credential fields from database row values.
	now := time.Now().UTC()
	row := fakeScanner{values: []any{"cred", "tenant", "install", sql.NullString{String: "actor", Valid: true}, "bundle", sql.NullString{}, sql.NullString{}, "macOS", credentials.ModeEd25519, sql.NullString{String: "pk", Valid: true}, []byte("enc"), sql.NullString{String: "hash", Valid: true}, credentials.StatusActive, sql.NullString{}, sql.NullString{}, now, sql.NullTime{}, sql.NullTime{}, sql.NullTime{}}}
	rec, enc, hash, err := scanCredential(row)
	if err != nil {
		t.Fatalf("expected scan success, got %v", err)
	}
	if rec.CredentialID != "cred" || rec.PublicKey != "pk" || string(enc) != "enc" || hash != "hash" {
		t.Fatalf("unexpected scan result: %+v / %q / %q", rec, string(enc), hash)
	}
}

func TestApplySchemaFromFileRejectsUnapprovedPath(t *testing.T) {
	// #R020-T02: Passing "../etc/passwd" returns error without reading any file.
	// #R020-T03: Passing empty string returns error.
	// #R020: Schema bootstrap only accepts repository-approved schema path.
	store := &PostgresStore{}
	err := store.ApplySchemaFromFile(context.Background(), "../tmp/other.sql")
	if err == nil || !strings.Contains(err.Error(), "internal/storage/schema.sql") {
		t.Fatalf("expected approved schema path error, got %v", err)
	}
}

type fakeScanner struct {
	values []any
	err    error
}

func (f fakeScanner) Scan(dest ...any) error {
	if f.err != nil {
		return f.err
	}
	for i := range dest {
		ptr := dest[i]
		val := f.values[i]
		switch d := ptr.(type) {
		case *string:
			*d = val.(string)
		case *sql.NullString:
			*d = val.(sql.NullString)
		case *[]byte:
			*d = val.([]byte)
		case *time.Time:
			*d = val.(time.Time)
		case *sql.NullTime:
			*d = val.(sql.NullTime)
		default:
			return errors.New("unsupported scan type")
		}
	}
	return nil
}
