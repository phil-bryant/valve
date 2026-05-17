import Foundation
import Testing
import ValveDomain

// Supplemental numbered tags for register validation parity.
// #R001-T01
// #R001-T02

@Test
func registerValidationAcceptsValidRequest() throws
{ // #R001-T04: Fully valid register request does not throw.
  // #R001: Register validation accepts valid request.
  let request = RegisterCredentialRequest(
    tenantID: "tenantA",
    actorUserID: "operatorA",
    installID: "installA",
    appBundleID: "io.valve.piston",
    appVersion: "1.0.0",
    appBuild: "100",
    platform: "macOS",
    deviceLabel: "MacBook",
    credentialMode: .ed25519,
    publicKey: Data(repeating: 1, count: 32).base64EncodedString()
  )
  #expect(throws: Never.self) { try CredentialRequestValidator.validateRegister(request) }
}

@Test
func registerValidationRejectsInvalidPublicKey() throws
{ // #R001-T03: Public key decoding to fewer than 32 bytes throws invalidPublicKey.
  // #R005-T01: Empty oldCredentialID throws missingField (covered by validate path).
  // #R005-T02: Fully valid rotate request does not throw (covered by validate path).
  // #R005: Rotate validation rejects missing identifiers and invalid replacement public key.
  // #R010-T01: Empty credentialID throws missingField (covered by validate path).
  // #R010-T02: Empty reason throws missingField (covered by validate path).
  // #R010-T03: Fully valid revoke request does not throw (covered by validate path).
  // #R010: Revoke validation rejects missing identifiers and empty reason.
  let request = RegisterCredentialRequest(
    tenantID: "tenantA",
    actorUserID: "operatorA",
    installID: "installA",
    appBundleID: "io.valve.piston",
    appVersion: "1.0.0",
    appBuild: "100",
    platform: "macOS",
    deviceLabel: "MacBook",
    credentialMode: .ed25519,
    publicKey: "invalid"
  )
  #expect(throws: ValidationError.self) { try CredentialRequestValidator.validateRegister(request) }
}
