package credentials

import (
	"crypto/rand"
	"encoding/base32"
	"strings"
)

// #R001: Generate opaque credential IDs from cryptographically random bytes.
func NewCredentialID() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	enc := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(buf)
	// #R005: Enforce cred_ prefix and lower-case stable ID shape.
	return "cred_" + strings.ToLower(enc), nil
}
