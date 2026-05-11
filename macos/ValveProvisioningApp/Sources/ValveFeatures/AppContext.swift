import Foundation
import ValveDomain
import ValveNetworking
import ValveSecurity

public actor AppAuditLogger
{ private let url: URL
  private let encoder: JSONEncoder

  public init()
  { let manager = FileManager.default
    let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: "/tmp")
    let appDirectory = directory.appending(path: "ValveProvisioningApp", directoryHint: .isDirectory)
    try? manager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    url = appDirectory.appending(path: "audit.jsonl")
    encoder = JSONEncoder()
  }

  public func write(action: String, status: String, details: String)
  { let entry = AuditEntry(timestamp: ISO8601DateFormatter().string(from: Date()), action: action, status: status, details: details)
    let payload = ((try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}") + "\n"
    if let data = payload.data(using: .utf8)
    { if FileManager.default.fileExists(atPath: url.path)
      { if let handle = try? FileHandle(forWritingTo: url)
        { _ = try? handle.seekToEnd()
          try? handle.write(contentsOf: data)
          try? handle.close()
        }
      } else
      { try? data.write(to: url)
      }
    }
  }
}

private struct AuditEntry: Codable, Sendable
{ let timestamp: String
  let action: String
  let status: String
  let details: String
}

public struct AppContext: Sendable
{ public let environment: ValveEnvironment
  public let apiClient: any ValveAPIClientProtocol
  public let keyManager: any CredentialKeyManaging
  public let auditLogger: AppAuditLogger

  public init(environment: ValveEnvironment, apiClient: any ValveAPIClientProtocol, keyManager: any CredentialKeyManaging, auditLogger: AppAuditLogger)
  { self.environment = environment
    self.apiClient = apiClient
    self.keyManager = keyManager
    self.auditLogger = auditLogger
  }

  public static func liveFromEnvironment() -> AppContext
  { let env = ProcessInfo.processInfo.environment
    let baseURLString = env["VALVE_BASE_URL"] ?? "http://localhost:8080"
    let url = URL(string: baseURLString) ?? URL(string: "http://localhost:8080")!
    let valveEnvironment = ValveEnvironment(
      baseURL: url,
      tenantID: env["VALVE_TENANT_ID"] ?? "tenant-dev",
      installID: env["VALVE_INSTALL_ID"] ?? "install-dev",
      actorUserID: env["VALVE_ACTOR_USER_ID"] ?? "operator-dev"
    )
    let keychain = KeychainStore()
    let manager = CredentialKeyManager(keychainStore: keychain)
    let client = ValveAPIClient(environment: valveEnvironment)
    let context = AppContext(environment: valveEnvironment, apiClient: client, keyManager: manager, auditLogger: AppAuditLogger())
    return context
  }
}
