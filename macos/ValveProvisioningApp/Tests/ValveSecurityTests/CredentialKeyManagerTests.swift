import Foundation
import Testing
import ValveDomain
import ValveSecurity

private final class MockKeychainStore: KeychainStoreProtocol, @unchecked Sendable
{ var saved: [(key: String, data: Data)] = []

  func save(key: String, data: Data) throws
  { saved.append((key: key, data: data))
  }

  func load(key: String) throws -> Data?
  { let match = saved.first(where: { $0.key == key })
    return match?.data
  }
}

// #R001-T01: makePublicKeyBase64 returns base64 string that decodes to exactly 32 bytes.
// #R001-T02: Two successive calls return distinct public keys.
// #R001: Generate Ed25519 key pairs and return public key as base64 with raw private key data.
// #R005-T01: storePrivateKey calls keychainStore.save with expected key path.
// #R005-T02: storeHMACSecret calls keychainStore.save with UTF-8 encoded data.
// #R005: Persist private key and HMAC secret material through keychain store abstraction.
@Test
func makePublicKeyBase64ProducesValid32ByteKey() throws
{ let store = MockKeychainStore()
  let manager = CredentialKeyManager(keychainStore: store)
  let result = try manager.makePublicKeyBase64()
  let decoded = Data(base64Encoded: result.publicKey)
  #expect(decoded?.count == 32)
  #expect(result.privateKeyData.count == 32)
}

@Test
func makePublicKeyBase64ProducesDistinctKeys() throws
{ let store = MockKeychainStore()
  let manager = CredentialKeyManager(keychainStore: store)
  let a = try manager.makePublicKeyBase64()
  let b = try manager.makePublicKeyBase64()
  #expect(a.publicKey != b.publicKey)
}

@Test
func storePrivateKeyPersistsToKeychainWithExpectedPath() throws
{ let store = MockKeychainStore()
  let manager = CredentialKeyManager(keychainStore: store)
  let keyData = Data(repeating: 0xAB, count: 32)
  try manager.storePrivateKey(keyData, for: "cred_xyz")
  #expect(store.saved.count == 1)
  #expect(store.saved[0].key == "credential.cred_xyz.privateKey")
  #expect(store.saved[0].data == keyData)
}

@Test
func storeHMACSecretPersistsUTF8EncodedData() throws
{ let store = MockKeychainStore()
  let manager = CredentialKeyManager(keychainStore: store)
  try manager.storeHMACSecret("secret-value", for: "cred_abc")
  #expect(store.saved.count == 1)
  #expect(store.saved[0].key == "credential.cred_abc.hmacSecret")
  #expect(store.saved[0].data == Data("secret-value".utf8))
}
