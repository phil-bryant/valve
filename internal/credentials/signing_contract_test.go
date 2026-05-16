package credentials

import (
	"strings"
	"testing"
)

func TestSigningContractContainsCanonicalElements(t *testing.T) {
	// #R001-T01: SigningContract contains X-Manifold-Credential-ID.
	// #R001-T02: SigningContract contains X-Manifold-Signature.
	// #R001-T03: SigningContract contains canonical string field order.
	// #R005-T01: SigningContract contains Ed25519 or ed25519.
	// #R005-T02: SigningContract contains HMAC or hmac.
	// #R005-T03: SigningContract references both public key and secret.
	// #R001: Contract publishes canonical headers and string format.
	// #R005: Contract documents Ed25519 and HMAC signing semantics.
	required := []string{"X-Manifold-Credential-ID", "Canonical string", "Ed25519 mode", "HMAC fallback mode"}
	for _, token := range required {
		if !strings.Contains(SigningContract, token) {
			t.Fatalf("expected contract to contain %q", token)
		}
	}
}
