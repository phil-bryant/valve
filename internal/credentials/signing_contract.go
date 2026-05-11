package credentials

const SigningContract = `
Piston -> Manifold request signing contract:

Headers:
- X-Manifold-Credential-ID
- X-Manifold-Timestamp (RFC3339)
- X-Manifold-Batch-ID (UUID)
- X-Manifold-Body-SHA256 (base64url(sha256(body)))
- X-Manifold-Signature (base64url(signature))

Canonical string:
METHOD + "\n" +
PATH + "\n" +
TIMESTAMP + "\n" +
BATCH_ID + "\n" +
BODY_SHA256

Ed25519 mode:
- Signature is ed25519_sign(canonical_string) with the client private key.
- Manifold verifies with the Valve-registered public key.

HMAC fallback mode:
- Signature is HMAC-SHA256(secret, canonical_string).
- Manifold verifies with the Valve-managed secret.
`
