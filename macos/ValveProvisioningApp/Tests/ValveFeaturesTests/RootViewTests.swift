import Foundation
import Testing
import ValveDomain
import ValveFeatures
import ValveNetworking
import ValveSecurity

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

private struct StubKeyManager: CredentialKeyManaging
{ func makePublicKeyBase64() throws -> (publicKey: String, privateKeyData: Data)
  { ("stub-public-key", Data())
  }
  func storePrivateKey(_ privateKeyData: Data, for credentialID: String) throws {}
  func storeHMACSecret(_ secret: String, for credentialID: String) throws {}
}

@Test
func rootViewModelInitializesEnvironmentDefaults() async throws
{ // #R001-T03: RootViewModel initializes tenant and install identifiers from AppContext environment.
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
func rootViewModelHealthCheckMarksHealthyWhenAPIResponds() async throws
{ // #R005-T03: checkHealth sets isHealthy true when healthz and readyz succeed.
  // #R005: Root view model performs health and readiness checks through API client.
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
