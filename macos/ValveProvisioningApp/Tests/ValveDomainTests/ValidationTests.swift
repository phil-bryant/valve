import Foundation
import Testing
import ValveDomain

@Test
func registerValidationAcceptsValidRequest() throws
{ let request = RegisterCredentialRequest(
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
{ let request = RegisterCredentialRequest(
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
