import SwiftUI
import ValveDomain

@MainActor
public final class RootViewModel: ObservableObject
{ @Published public var tenantID: String
  @Published public var installID: String
  @Published public var actorUserID: String
  @Published public var appBundleID: String
  @Published public var appVersion: String
  @Published public var appBuild: String
  @Published public var deviceLabel: String
  @Published public var revokeCredentialID: String
  @Published public var revokeReason: String
  @Published public var rotateOldCredentialID: String
  @Published public var rotateDeviceLabel: String
  @Published public var lastMessage: String
  @Published public var isHealthy: Bool
  @Published public var records: [CredentialRecord]
  @Published public var selectedMode: CredentialMode

  private let context: AppContext

  public init(context: AppContext)
  { self.context = context
    tenantID = context.environment.tenantID
    installID = context.environment.installID
    actorUserID = context.environment.actorUserID
    appBundleID = "io.valve.piston"
    appVersion = "1.0.0"
    appBuild = "100"
    deviceLabel = Host.current().localizedName ?? "macOS Device"
    revokeCredentialID = ""
    revokeReason = "Operator offboarding request"
    rotateOldCredentialID = ""
    rotateDeviceLabel = Host.current().localizedName ?? "macOS Device"
    lastMessage = ""
    isHealthy = false
    records = []
    selectedMode = .ed25519
  }

  public func checkHealth() async
  { do
    { let isLive = try await context.apiClient.healthCheck()
      let isReady = try await context.apiClient.readinessCheck()
      isHealthy = isLive && isReady
      await context.auditLogger.write(action: "health_check", status: isHealthy ? "ok" : "failed", details: "healthz+readyz")
    } catch
    { isHealthy = false
      lastMessage = "Health check failed: \(error.localizedDescription)"
      await context.auditLogger.write(action: "health_check", status: "error", details: error.localizedDescription)
    }
  }

  public func provision() async
  { do
    { let generated = try context.keyManager.makePublicKeyBase64()
      let request = RegisterCredentialRequest(
        tenantID: tenantID,
        actorUserID: actorUserID,
        installID: installID,
        appBundleID: appBundleID,
        appVersion: appVersion,
        appBuild: appBuild,
        platform: "macOS",
        deviceLabel: deviceLabel,
        credentialMode: selectedMode,
        publicKey: generated.publicKey
      )
      try CredentialRequestValidator.validateRegister(request)
      let response = try await withRetry(maxAttempts: 3) { try await self.context.apiClient.registerCredential(request) }
      try context.keyManager.storePrivateKey(generated.privateKeyData, for: response.credentialID)
      if let secret = response.secret { try context.keyManager.storeHMACSecret(secret, for: response.credentialID) }
      lastMessage = "Provisioned credential \(response.credentialID)"
      await context.auditLogger.write(action: "register", status: "ok", details: response.credentialID)
      await refreshList()
    } catch
    { lastMessage = "Provision failed: \(error.localizedDescription)"
      await context.auditLogger.write(action: "register", status: "error", details: error.localizedDescription)
    }
  }

  public func revoke() async
  { do
    { let request = RevokeCredentialRequest(
        tenantID: tenantID,
        actorUserID: actorUserID,
        credentialID: revokeCredentialID,
        reason: revokeReason
      )
      try CredentialRequestValidator.validateRevoke(request)
      let response = try await withRetry(maxAttempts: 3) { try await self.context.apiClient.revokeCredential(request) }
      lastMessage = "Revoked credential \(response.credentialID)"
      await context.auditLogger.write(action: "revoke", status: "ok", details: response.credentialID)
      await refreshList()
    } catch
    { lastMessage = "Revoke failed: \(error.localizedDescription)"
      await context.auditLogger.write(action: "revoke", status: "error", details: error.localizedDescription)
    }
  }

  public func rotate() async
  { do
    { let generated = try context.keyManager.makePublicKeyBase64()
      let request = RotateCredentialRequest(
        tenantID: tenantID,
        actorUserID: actorUserID,
        oldCredentialID: rotateOldCredentialID,
        installID: installID,
        credentialMode: selectedMode,
        newPublicKey: generated.publicKey,
        appVersion: appVersion,
        appBuild: appBuild,
        deviceLabel: rotateDeviceLabel
      )
      try CredentialRequestValidator.validateRotate(request)
      let response = try await withRetry(maxAttempts: 3) { try await self.context.apiClient.rotateCredential(request) }
      try context.keyManager.storePrivateKey(generated.privateKeyData, for: response.newCredentialID)
      if let secret = response.secret { try context.keyManager.storeHMACSecret(secret, for: response.newCredentialID) }
      lastMessage = "Rotated \(response.oldCredentialID) -> \(response.newCredentialID)"
      await context.auditLogger.write(action: "rotate", status: "ok", details: response.newCredentialID)
      await refreshList()
    } catch
    { lastMessage = "Rotate failed: \(error.localizedDescription)"
      await context.auditLogger.write(action: "rotate", status: "error", details: error.localizedDescription)
    }
  }

  public func refreshList() async
  { do
    { let result = try await withRetry(maxAttempts: 3) { try await self.context.apiClient.listCredentials(tenantID: self.tenantID, installID: self.installID) }
      records = result
      await context.auditLogger.write(action: "list", status: "ok", details: "\(result.count) records")
    } catch
    { lastMessage = "List failed: \(error.localizedDescription)"
      await context.auditLogger.write(action: "list", status: "error", details: error.localizedDescription)
    }
  }

  private func withRetry<T>(maxAttempts: Int, operation: @escaping @Sendable () async throws -> T) async throws -> T
  { var attempts = 0
    var value: T?
    var finalError: Error?
    while attempts < maxAttempts && value == nil
    { do
      { value = try await operation()
      } catch
      { finalError = error
        attempts += 1
        if attempts < maxAttempts
        { let delay = UInt64(attempts) * 200_000_000
          try? await Task.sleep(nanoseconds: delay)
        }
      }
    }
    if let value { return value }
    throw finalError ?? ValidationError.missingField("Unknown retry error")
  }
}

public struct RootView: View
{ @StateObject private var model: RootViewModel

  public init(context: AppContext)
  { _model = StateObject(wrappedValue: RootViewModel(context: context))
  }

  public var body: some View
  { TabView
    { ProvisionView(model: model).tabItem { Text("Provision") }
      RevokeView(model: model).tabItem { Text("Deprovision") }
      RotateView(model: model).tabItem { Text("Rotate") }
      InventoryView(model: model).tabItem { Text("Inventory") }
    }
    .frame(minWidth: 920, minHeight: 700)
    .task { await model.checkHealth(); await model.refreshList() }
  }
}

private struct ProvisionView: View
{ @ObservedObject var model: RootViewModel

  var body: some View
  { VStack(alignment: .leading)
    { HStack { Text("Environment").font(.headline); Spacer(); HealthBadge(isHealthy: model.isHealthy) }
      LabeledField(title: "Base Tenant", text: $model.tenantID)
      LabeledField(title: "Install ID", text: $model.installID)
      LabeledField(title: "Actor User ID", text: $model.actorUserID)
      LabeledField(title: "App Bundle ID", text: $model.appBundleID)
      LabeledField(title: "App Version", text: $model.appVersion)
      LabeledField(title: "App Build", text: $model.appBuild)
      LabeledField(title: "Device Label", text: $model.deviceLabel)
      Picker("Credential Mode", selection: $model.selectedMode)
      { ForEach(CredentialMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Button("Provision Credential")
      { Task { await model.provision() }
      }
      .buttonStyle(.borderedProminent)
      Text(model.lastMessage).font(.footnote).textSelection(.enabled)
      Spacer()
    }
    .padding()
  }
}

private struct RevokeView: View
{ @ObservedObject var model: RootViewModel

  var body: some View
  { VStack(alignment: .leading)
    { LabeledField(title: "Tenant ID", text: $model.tenantID)
      LabeledField(title: "Actor User ID", text: $model.actorUserID)
      LabeledField(title: "Credential ID", text: $model.revokeCredentialID)
      LabeledField(title: "Reason", text: $model.revokeReason)
      Button("Revoke Credential")
      { Task { await model.revoke() }
      }
      .buttonStyle(.borderedProminent)
      Text(model.lastMessage).font(.footnote).textSelection(.enabled)
      Spacer()
    }
    .padding()
  }
}

private struct RotateView: View
{ @ObservedObject var model: RootViewModel

  var body: some View
  { VStack(alignment: .leading)
    { LabeledField(title: "Tenant ID", text: $model.tenantID)
      LabeledField(title: "Install ID", text: $model.installID)
      LabeledField(title: "Actor User ID", text: $model.actorUserID)
      LabeledField(title: "Old Credential ID", text: $model.rotateOldCredentialID)
      LabeledField(title: "App Version", text: $model.appVersion)
      LabeledField(title: "App Build", text: $model.appBuild)
      LabeledField(title: "Device Label", text: $model.rotateDeviceLabel)
      Picker("Credential Mode", selection: $model.selectedMode)
      { ForEach(CredentialMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Button("Rotate Credential")
      { Task { await model.rotate() }
      }
      .buttonStyle(.borderedProminent)
      Text(model.lastMessage).font(.footnote).textSelection(.enabled)
      Spacer()
    }
    .padding()
  }
}

private struct InventoryView: View
{ @ObservedObject var model: RootViewModel

  var body: some View
  { VStack(alignment: .leading)
    { HStack
      { LabeledField(title: "Tenant ID", text: $model.tenantID)
        LabeledField(title: "Install ID", text: $model.installID)
        Button("Refresh")
        { Task { await model.refreshList() }
        }
      }
      Table(model.records)
      { TableColumn("Credential ID") { Text($0.credentialID) }
        TableColumn("Status") { Text($0.status) }
        TableColumn("Device") { Text($0.deviceLabel) }
        TableColumn("Version") { Text($0.appVersion) }
        TableColumn("Created") { Text($0.createdAt) }
      }
      Text(model.lastMessage).font(.footnote).textSelection(.enabled)
    }
    .padding()
  }
}

private struct LabeledField: View
{ let title: String
  @Binding var text: String

  var body: some View
  { HStack
    { Text(title).frame(width: 160, alignment: .leading)
      TextField(title, text: $text).textFieldStyle(.roundedBorder)
    }
  }
}

private struct HealthBadge: View
{ let isHealthy: Bool

  var body: some View
  { Text(isHealthy ? "API Healthy" : "API Unreachable")
    .font(.caption.bold())
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(isHealthy ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
    .cornerRadius(8)
  }
}
