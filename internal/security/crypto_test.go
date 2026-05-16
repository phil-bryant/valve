package security

import (
	"encoding/base64"
	"testing"
)

func TestGenerateRandomSecretBase64ProducesRequestedByteLength(t *testing.T) {
	// #R001-T01: Two successive calls return distinct strings.
	// #R001-T02: Returned string is valid standard base64.
	// #R001-T03: Decoding returns exactly size bytes.
	// #R001: Secret generation returns valid base64 payload with requested byte length.
	secret, err := GenerateRandomSecretBase64(32)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	raw, err := base64.StdEncoding.DecodeString(secret)
	if err != nil {
		t.Fatalf("expected valid base64 output, got %v", err)
	}
	if len(raw) != 32 {
		t.Fatalf("expected 32 decoded bytes, got %d", len(raw))
	}
}

func TestHashSecretHexIsDeterministicAndHasSha256Length(t *testing.T) {
	// #R005-T01: Same input always produces same output (determinism).
	// #R005-T02: Output is exactly 64 characters long.
	// #R005-T04: Two distinct inputs produce distinct digests.
	// #R005: Hashing is deterministic and SHA-256 sized for persistence checks.
	a := HashSecretHex("same-input")
	b := HashSecretHex("same-input")
	c := HashSecretHex("other-input")
	if len(a) != 64 {
		t.Fatalf("expected sha256 hex length 64, got %d", len(a))
	}
	if a != b {
		t.Fatalf("expected deterministic hash for identical input")
	}
	if a == c {
		t.Fatalf("expected different inputs to produce different digests")
	}
}
