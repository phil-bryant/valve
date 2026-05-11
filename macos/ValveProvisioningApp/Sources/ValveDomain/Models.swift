import Foundation

public enum CredentialMode: String, Codable, CaseIterable, Sendable
{ case ed25519
  case hmac_sha256
}

public struct RegisterCredentialRequest: Codable, Sendable
{ public let tenantID: String
  public let actorUserID: String
  public let installID: String
  public let appBundleID: String
  public let appVersion: String
  public let appBuild: String
  public let platform: String
  public let deviceLabel: String
  public let credentialMode: CredentialMode
  public let publicKey: String

  public init(
    tenantID: String,
    actorUserID: String,
    installID: String,
    appBundleID: String,
    appVersion: String,
    appBuild: String,
    platform: String,
    deviceLabel: String,
    credentialMode: CredentialMode,
    publicKey: String
  )
  { self.tenantID = tenantID
    self.actorUserID = actorUserID
    self.installID = installID
    self.appBundleID = appBundleID
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.platform = platform
    self.deviceLabel = deviceLabel
    self.credentialMode = credentialMode
    self.publicKey = publicKey
  }

  enum CodingKeys: String, CodingKey
  { case tenantID = "tenant_id"
    case actorUserID = "actor_user_id"
    case installID = "install_id"
    case appBundleID = "app_bundle_id"
    case appVersion = "app_version"
    case appBuild = "app_build"
    case platform
    case deviceLabel = "device_label"
    case credentialMode = "credential_mode"
    case publicKey = "public_key"
  }
}

public struct RegisterCredentialResponse: Codable, Sendable
{ public let credentialID: String
  public let tenantScope: String
  public let installID: String
  public let uploadEndpoint: String
  public let signingAlgorithm: String
  public let secret: String?
  public let status: String

  enum CodingKeys: String, CodingKey
  { case credentialID = "credential_id"
    case tenantScope = "tenant_scope"
    case installID = "install_id"
    case uploadEndpoint = "upload_endpoint"
    case signingAlgorithm = "signing_algorithm"
    case secret
    case status
  }
}

public struct RevokeCredentialRequest: Codable, Sendable
{ public let tenantID: String
  public let actorUserID: String
  public let credentialID: String
  public let reason: String

  public init(tenantID: String, actorUserID: String, credentialID: String, reason: String)
  { self.tenantID = tenantID
    self.actorUserID = actorUserID
    self.credentialID = credentialID
    self.reason = reason
  }

  enum CodingKeys: String, CodingKey
  { case tenantID = "tenant_id"
    case actorUserID = "actor_user_id"
    case credentialID = "credential_id"
    case reason
  }
}

public struct RevokeCredentialResponse: Codable, Sendable
{ public let credentialID: String
  public let status: String
  public let revokedAt: String

  enum CodingKeys: String, CodingKey
  { case credentialID = "credential_id"
    case status
    case revokedAt = "revoked_at"
  }
}

public struct RotateCredentialRequest: Codable, Sendable
{ public let tenantID: String
  public let actorUserID: String
  public let oldCredentialID: String
  public let installID: String
  public let credentialMode: CredentialMode
  public let newPublicKey: String
  public let appVersion: String
  public let appBuild: String
  public let deviceLabel: String

  public init(
    tenantID: String,
    actorUserID: String,
    oldCredentialID: String,
    installID: String,
    credentialMode: CredentialMode,
    newPublicKey: String,
    appVersion: String,
    appBuild: String,
    deviceLabel: String
  )
  { self.tenantID = tenantID
    self.actorUserID = actorUserID
    self.oldCredentialID = oldCredentialID
    self.installID = installID
    self.credentialMode = credentialMode
    self.newPublicKey = newPublicKey
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.deviceLabel = deviceLabel
  }

  enum CodingKeys: String, CodingKey
  { case tenantID = "tenant_id"
    case actorUserID = "actor_user_id"
    case oldCredentialID = "old_credential_id"
    case installID = "install_id"
    case credentialMode = "credential_mode"
    case newPublicKey = "new_public_key"
    case appVersion = "app_version"
    case appBuild = "app_build"
    case deviceLabel = "device_label"
  }
}

public struct RotateCredentialResponse: Codable, Sendable
{ public let oldCredentialID: String
  public let oldStatus: String
  public let newCredentialID: String
  public let tenantScope: String
  public let installID: String
  public let signingAlgorithm: String
  public let status: String
  public let secret: String?

  enum CodingKeys: String, CodingKey
  { case oldCredentialID = "old_credential_id"
    case oldStatus = "old_status"
    case newCredentialID = "new_credential_id"
    case tenantScope = "tenant_scope"
    case installID = "install_id"
    case signingAlgorithm = "signing_algorithm"
    case status
    case secret
  }
}

public struct CredentialRecord: Codable, Identifiable, Sendable
{ public let credentialID: String
  public let tenantID: String
  public let installID: String
  public let deviceLabel: String
  public let appBundleID: String
  public let appVersion: String
  public let appBuild: String
  public let platform: String
  public let status: String
  public let createdAt: String
  public let revokedAt: String?

  public var id: String { credentialID }

  enum CodingKeys: String, CodingKey
  { case credentialID = "credential_id"
    case tenantID = "tenant_id"
    case installID = "install_id"
    case deviceLabel = "device_label"
    case appBundleID = "app_bundle_id"
    case appVersion = "app_version"
    case appBuild = "app_build"
    case platform
    case status
    case createdAt = "created_at"
    case revokedAt = "revoked_at"
  }
}

public struct ListCredentialsResponse: Codable, Sendable
{ public let credentials: [CredentialRecord]
}

public struct ErrorEnvelope: Codable, Sendable
{ public let error: String
}
