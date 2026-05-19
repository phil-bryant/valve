package security

import "testing"

func FuzzIsServiceAuthorized(f *testing.F) {
	f.Add("expected-key", "provided-key")
	f.Fuzz(func(t *testing.T, expected, provided string) {
		_ = IsServiceAuthorized(expected, provided)
	})
}
