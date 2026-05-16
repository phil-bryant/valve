import Foundation
import Testing
import ValveSecurity

// #R001-T01: Saving and loading the same key returns the original data.
// #R001-T02: Saving to the same key twice overwrites without error.
// #R001: Persist arbitrary data to macOS Keychain under service-scoped account key.
// #R005-T01: Loading a non-existent key returns nil without throwing.
// #R005: Load previously persisted data, returning nil when item does not exist.
@Test
func keychainStoreRoundTripsData() throws
{ let store = KeychainStore(serviceName: "io.valve.test.\(UUID().uuidString)")
  let key = "test-key-\(UUID().uuidString)"
  let data = Data("hello-keychain".utf8)
  try store.save(key: key, data: data)
  let loaded = try store.load(key: key)
  #expect(loaded == data)
  // Overwrite
  let data2 = Data("overwritten".utf8)
  try store.save(key: key, data: data2)
  let loaded2 = try store.load(key: key)
  #expect(loaded2 == data2)
}

@Test
func keychainStoreReturnsNilForMissingKey() throws
{ let store = KeychainStore(serviceName: "io.valve.test.\(UUID().uuidString)")
  let loaded = try store.load(key: "nonexistent-\(UUID().uuidString)")
  #expect(loaded == nil)
}
