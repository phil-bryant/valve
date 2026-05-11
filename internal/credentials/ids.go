package credentials

import (
	"crypto/rand"
	"encoding/base32"
	"strings"
)

func NewCredentialID() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	enc := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(buf)
	return "cred_" + strings.ToLower(enc), nil
}
