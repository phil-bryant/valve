import Foundation
import Testing
import ValveDomain

// #R001-T01: CredentialMode.ed25519.rawValue equals "ed25519".
// #R001-T02: CredentialMode.hmac_sha256.rawValue equals "hmac_sha256".
// #R001: Credential mode enum with snake_case raw values matching Valve API wire format.
// #R005-T01: Encoding RegisterCredentialRequest produces JSON with tenant_id key.
// #R005-T02: Decoding JSON payload with credential_id key produces valid RegisterCredentialResponse.
// #R005-T03: CredentialRecord conforms to Identifiable with id returning credentialID.
// #R005: Request and response models with JSON coding keys matching Valve API snake_case contract.
@Test
func credentialModeRawValuesMatchAPIContract()
{ #expect(CredentialMode.ed25519.rawValue == "ed25519")
  #expect(CredentialMode.hmac_sha256.rawValue == "hmac_sha256")
}

@Test
func registerRequestEncodesWithSnakeCaseKeys() throws
{ let request = RegisterCredentialRequest(
    tenantID: "t1",
    actorUserID: "a1",
    installID: "i1",
    appBundleID: "io.valve.test",
    appVersion: "1.0",
    appBuild: "1",
    platform: "macOS",
    deviceLabel: "Mac",
    credentialMode: .ed25519,
    publicKey: Data(repeating: 1, count: 32).base64EncodedString()
  )
  let data = try JSONEncoder().encode(request)
  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
  #expect(json?["tenant_id"] as? String == "t1")
  #expect(json?["actor_user_id"] as? String == "a1")
}

@Test
func credentialRecordIdentifiableUsesCredentialID()
{ let json = """
  {"credential_id":"cred_1","tenant_id":"t","install_id":"i","device_label":"Mac","app_bundle_id":"b","app_version":"1","app_build":"1","platform":"macOS","status":"active","created_at":"2026-01-01T00:00:00Z"}
  """.data(using: .utf8)!
  let record = try! JSONDecoder().decode(CredentialRecord.self, from: json)
  #expect(record.id == "cred_1")
}
