import Foundation
import Testing
import ValveDomain
import ValveFeatures
import ValveNetworking
import ValveSecurity

// #R001: Root view model supports credential provisioning lifecycle actions.
// #R005: Root view model health and list coverage shares API client test doubles.

private struct HealthyStubAPIClient: ValveAPIClientProtocol
{ func registerCredential(_ request: RegisterCredentialRequest) async throws -> RegisterCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func revokeCredential(_ request: RevokeCredentialRequest) async throws -> RevokeCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func rotateCredential(_ request: RotateCredentialRequest) async throws -> RotateCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func listCredentials(tenantID: String, installID: String) async throws -> [CredentialRecord]
  { []
  }
  func healthCheck() async throws -> Bool
  { true
  }
  func readinessCheck() async throws -> Bool
  { true
  }
}

private struct RevokeStubAPIClient: ValveAPIClientProtocol
{ func registerCredential(_ request: RegisterCredentialRequest) async throws -> RegisterCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func revokeCredential(_ request: RevokeCredentialRequest) async throws -> RevokeCredentialResponse
  { let json = """
    {"credential_id":"\(request.credentialID)","status":"revoked","revoked_at":"2026-05-19T00:00:00Z"}
    """.data(using: .utf8)!
    return try JSONDecoder().decode(RevokeCredentialResponse.self, from: json)
  }
  func rotateCredential(_ request: RotateCredentialRequest) async throws -> RotateCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func listCredentials(tenantID: String, installID: String) async throws -> [CredentialRecord]
  { []
  }
  func healthCheck() async throws -> Bool
  { true
  }
  func readinessCheck() async throws -> Bool
  { true
  }
}

private struct ListStubAPIClient: ValveAPIClientProtocol
{ func registerCredential(_ request: RegisterCredentialRequest) async throws -> RegisterCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func revokeCredential(_ request: RevokeCredentialRequest) async throws -> RevokeCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func rotateCredential(_ request: RotateCredentialRequest) async throws -> RotateCredentialResponse
  { throw NSError(domain: "test", code: 1)
  }
  func listCredentials(tenantID: String, installID: String) async throws -> [CredentialRecord]
  { let json = """
    [{"credential_id":"cred-list-1","tenant_id":"\(tenantID)","install_id":"\(installID)","device_label":"MacBook","app_bundle_id":"com.example.valve","app_version":"1.0","app_build":"100","platform":"macOS","status":"active","created_at":"2026-05-19T00:00:00Z"}]
    """.data(using: .utf8)!
    return try JSONDecoder().decode([CredentialRecord].self, from: json)
  }
  func healthCheck() async throws -> Bool
  { true
  }
  func readinessCheck() async throws -> Bool
  { true
  }
}

private struct StubKeyManager: CredentialKeyManaging
{ func makePublicKeyBase64() throws -> (publicKey: String, privateKeyData: Data)
  { ("stub-public-key", Data())
  }
  func storePrivateKey(_ privateKeyData: Data, for credentialID: String) throws {}
  func storeHMACSecret(_ secret: String, for credentialID: String) throws {}
}

@Test
func rootViewModelRevokeUpdatesLastMessage() async throws
{ // #R001-T02: revoke with mock API client updates lastMessage to contain revoked credential ID.
  // #R001: Root view model supports credential provisioning lifecycle actions.
  let environment = ValveEnvironment(
    baseURL: URL(string: "http://localhost:8090")!,
    tenantID: "tenant-revoke",
    installID: "install-revoke",
    actorUserID: "operator-revoke"
  )
  let context = AppContext(
    environment: environment,
    apiClient: RevokeStubAPIClient(),
    keyManager: StubKeyManager(),
    auditLogger: AppAuditLogger()
  )
  let model = await MainActor.run { RootViewModel(context: context) }
  await MainActor.run {
    model.revokeCredentialID = "cred-revoke-1"
    model.revokeReason = "retired device"
  }
  await model.revoke()
  let lastMessage = await MainActor.run { model.lastMessage }
  #expect(lastMessage.contains("cred-revoke-1"))
}

@Test
func rootViewModelInitializesEnvironmentDefaults() async throws
{ // #R001-T04: RootViewModel initializes tenant and install identifiers from AppContext environment.
  // #R001: Root view model supports credential provisioning lifecycle actions.
  let environment = ValveEnvironment(
    baseURL: URL(string: "http://localhost:8090")!,
    tenantID: "tenant-root",
    installID: "install-root",
    actorUserID: "operator-root"
  )
  let context = AppContext(
    environment: environment,
    apiClient: HealthyStubAPIClient(),
    keyManager: StubKeyManager(),
    auditLogger: AppAuditLogger()
  )
  let model = await MainActor.run { RootViewModel(context: context) }
  let tenantID = await MainActor.run { model.tenantID }
  let installID = await MainActor.run { model.installID }
  #expect(tenantID == "tenant-root")
  #expect(installID == "install-root")
}

@Test
func rootViewModelRefreshListPopulatesRecordsFromAPI() async throws
{ // #R001-T03: refreshList populates records from the mock API response.
  // #R001: Root view model supports credential provisioning lifecycle actions.
  let environment = ValveEnvironment(
    baseURL: URL(string: "http://localhost:8090")!,
    tenantID: "tenant-list",
    installID: "install-list",
    actorUserID: "operator-list"
  )
  let context = AppContext(
    environment: environment,
    apiClient: ListStubAPIClient(),
    keyManager: StubKeyManager(),
    auditLogger: AppAuditLogger()
  )
  let model = await MainActor.run { RootViewModel(context: context) }
  await model.refreshList()
  let records = await MainActor.run { model.records }
  #expect(records.count == 1)
  #expect(records.first?.credentialID == "cred-list-1")
}

@Test
func rootViewModelHealthCheckMarksHealthyWhenAPIResponds() async throws
{ // #R001-T05: checkHealth sets isHealthy true when healthz and readyz succeed.
  // #R001: Root view model supports credential provisioning lifecycle actions.
  let environment = ValveEnvironment(
    baseURL: URL(string: "http://localhost:8090")!,
    tenantID: "tenant-dev",
    installID: "install-dev",
    actorUserID: "operator-dev"
  )
  let context = AppContext(
    environment: environment,
    apiClient: HealthyStubAPIClient(),
    keyManager: StubKeyManager(),
    auditLogger: AppAuditLogger()
  )
  let model = await MainActor.run { RootViewModel(context: context) }
  await model.checkHealth()
  let isHealthy = await MainActor.run { model.isHealthy }
  #expect(isHealthy)
}
