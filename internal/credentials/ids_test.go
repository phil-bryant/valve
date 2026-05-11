package credentials

import (
	"strings"
	"testing"
)

func TestNewCredentialIDFormat(t *testing.T) {
	// #R001: IDs are generated from random opaque values.
	// #R005: IDs include stable cred_ prefix and lower-case encoding.
	id, err := NewCredentialID()
	if err != nil {
		t.Fatalf("expected id generation success, got %v", err)
	}
	if !strings.HasPrefix(id, "cred_") {
		t.Fatalf("expected cred_ prefix, got %q", id)
	}
	if id != strings.ToLower(id) {
		t.Fatalf("expected lower-case id format, got %q", id)
	}
}
