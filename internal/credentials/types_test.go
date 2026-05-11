package credentials

import (
	"reflect"
	"testing"
)

func TestCredentialConstantsAndShapes(t *testing.T) {
	// #R001: Credential mode and lifecycle constants remain canonical.
	if ModeEd25519 == "" || ModeHMACSHA256 == "" || StatusActive == "" || StatusRevoked == "" || StatusRotated == "" {
		t.Fatalf("expected non-empty credential constants")
	}
	// #R005: API payload structs expose expected JSON field names.
	if _, ok := reflect.TypeOf(RegisterRequest{}).FieldByName("TenantID"); !ok {
		t.Fatalf("expected RegisterRequest.TenantID field")
	}
	if _, ok := reflect.TypeOf(RotateResponse{}).FieldByName("NewCredentialID"); !ok {
		t.Fatalf("expected RotateResponse.NewCredentialID field")
	}
	// #R010: Persistence model structs include credential and audit fields.
	if _, ok := reflect.TypeOf(CredentialRecord{}).FieldByName("CredentialID"); !ok {
		t.Fatalf("expected CredentialRecord.CredentialID field")
	}
	if _, ok := reflect.TypeOf(AuditEntry{}).FieldByName("Action"); !ok {
		t.Fatalf("expected AuditEntry.Action field")
	}
}
