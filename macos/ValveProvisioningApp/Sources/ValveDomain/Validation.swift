import Foundation

public enum ValidationError: Error, LocalizedError, Sendable
{ case missingField(String)
  case invalidPlatform
  case invalidPublicKey

  public var errorDescription: String?
  { let description: String
    switch self
    { case .missingField(let field): description = "\(field) is required."
      case .invalidPlatform: description = "Platform must be macOS."
      case .invalidPublicKey: description = "Public key must be base64 with 32 bytes."
    }
    return description
  }
}

public enum CredentialRequestValidator
{ public static func validateRegister(_ request: RegisterCredentialRequest) throws
  { try validateCommonFields(tenantID: request.tenantID, actorUserID: request.actorUserID, installID: request.installID)
    if request.platform != "macOS" { throw ValidationError.invalidPlatform }
    if request.appBundleID.isEmpty { throw ValidationError.missingField("app_bundle_id") }
    if request.appVersion.isEmpty { throw ValidationError.missingField("app_version") }
    if request.appBuild.isEmpty { throw ValidationError.missingField("app_build") }
    if request.deviceLabel.isEmpty { throw ValidationError.missingField("device_label") }
    if !isValidPublicKeyBase64(request.publicKey) { throw ValidationError.invalidPublicKey }
  }

  public static func validateRotate(_ request: RotateCredentialRequest) throws
  { try validateCommonFields(tenantID: request.tenantID, actorUserID: request.actorUserID, installID: request.installID)
    if request.oldCredentialID.isEmpty { throw ValidationError.missingField("old_credential_id") }
    if request.appVersion.isEmpty { throw ValidationError.missingField("app_version") }
    if request.appBuild.isEmpty { throw ValidationError.missingField("app_build") }
    if request.deviceLabel.isEmpty { throw ValidationError.missingField("device_label") }
    if !isValidPublicKeyBase64(request.newPublicKey) { throw ValidationError.invalidPublicKey }
  }

  public static func validateRevoke(_ request: RevokeCredentialRequest) throws
  { try validateCommonFields(tenantID: request.tenantID, actorUserID: request.actorUserID, installID: nil)
    if request.credentialID.isEmpty { throw ValidationError.missingField("credential_id") }
    if request.reason.isEmpty { throw ValidationError.missingField("reason") }
  }

  private static func validateCommonFields(tenantID: String, actorUserID: String, installID: String?) throws
  { if tenantID.isEmpty { throw ValidationError.missingField("tenant_id") }
    if actorUserID.isEmpty { throw ValidationError.missingField("actor_user_id") }
    if let installID, installID.isEmpty { throw ValidationError.missingField("install_id") }
  }

  public static func isValidPublicKeyBase64(_ value: String) -> Bool
  { let data = Data(base64Encoded: value)
    let isValid = data?.count == 32
    return isValid
  }
}
