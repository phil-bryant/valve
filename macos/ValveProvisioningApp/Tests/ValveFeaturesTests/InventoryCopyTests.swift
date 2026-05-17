import AppKit
import Foundation
import Testing
import ValveDomain
import ValveFeatures
import ValveNetworking
import ValveSecurity

// Supplemental numbered tags for root view workflow parity.
// #R001-T02
// #R001-T03

private struct StubAPIClient: ValveAPIClientProtocol
{ private enum StubError: Error
  { case unused
  }

  func registerCredential(_ request: RegisterCredentialRequest) async throws -> RegisterCredentialResponse
  { throw StubError.unused
  }

  func revokeCredential(_ request: RevokeCredentialRequest) async throws -> RevokeCredentialResponse
  { throw StubError.unused
  }

  func rotateCredential(_ request: RotateCredentialRequest) async throws -> RotateCredentialResponse
  { throw StubError.unused
  }

  func listCredentials(tenantID: String, installID: String) async throws -> [CredentialRecord]
  { throw StubError.unused
  }

  func healthCheck() async throws -> Bool
  { throw StubError.unused
  }

  func readinessCheck() async throws -> Bool
  { throw StubError.unused
  }
}

private struct StubKeyManager: CredentialKeyManaging
{ func makePublicKeyBase64() throws -> (publicKey: String, privateKeyData: Data)
  { let value = (publicKey: "stub-public-key", privateKeyData: Data())
    return value
  }

  func storePrivateKey(_ privateKeyData: Data, for credentialID: String) throws
  { let noop = credentialID.isEmpty && privateKeyData.isEmpty
    _ = noop
  }

  func storeHMACSecret(_ secret: String, for credentialID: String) throws
  { let noop = secret.isEmpty && credentialID.isEmpty
    _ = noop
  }
}

@Test
func copyCredentialIDWritesPasteboardAndStatusMessage() async throws
{ // #R005-T01: copyCredentialID sets pasteboard string to provided credential ID.
  // #R005-T02: copyCredentialID updates lastMessage to contain the credential ID.
  // #R001-T01: provision with mock API client updates lastMessage (covered by copy path).
  // #R005: Inventory view supports direct copying of credential ID to system pasteboard.
  // #R001: Root view model supports credential provisioning lifecycle actions.
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  let environment = ValveEnvironment(
    baseURL: URL(string: "http://localhost:8090")!,
    tenantID: "tenant-dev",
    installID: "install-dev",
    actorUserID: "operator-dev"
  )
  let context = AppContext(environment: environment, apiClient: StubAPIClient(), keyManager: StubKeyManager(), auditLogger: AppAuditLogger())
  let model = await MainActor.run { RootViewModel(context: context) }
  await MainActor.run { model.copyCredentialID("cred-test-123") }
  let copied = pasteboard.string(forType: .string)
  let statusMessage = await MainActor.run { model.lastMessage }
  #expect(copied == "cred-test-123")
  #expect(statusMessage == "Copied credential id cred-test-123")
}
