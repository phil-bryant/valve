import CryptoKit
import Foundation
import ValveDomain

public protocol CredentialKeyManaging: Sendable
{ func makePublicKeyBase64() throws -> (publicKey: String, privateKeyData: Data)
  func storePrivateKey(_ privateKeyData: Data, for credentialID: String) throws
  func storeHMACSecret(_ secret: String, for credentialID: String) throws
}

public struct CredentialKeyManager: CredentialKeyManaging
{ private let keychainStore: any KeychainStoreProtocol

  public init(keychainStore: any KeychainStoreProtocol)
  { self.keychainStore = keychainStore
  }

  public func makePublicKeyBase64() throws -> (publicKey: String, privateKeyData: Data)
  { let privateKey = Curve25519.Signing.PrivateKey()
    let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
    let privateKeyData = privateKey.rawRepresentation
    let value = (publicKey: publicKey, privateKeyData: privateKeyData)
    return value
  }

  public func storePrivateKey(_ privateKeyData: Data, for credentialID: String) throws
  { try keychainStore.save(key: "credential.\(credentialID).privateKey", data: privateKeyData)
  }

  public func storeHMACSecret(_ secret: String, for credentialID: String) throws
  { let data = Data(secret.utf8)
    try keychainStore.save(key: "credential.\(credentialID).hmacSecret", data: data)
  }
}
