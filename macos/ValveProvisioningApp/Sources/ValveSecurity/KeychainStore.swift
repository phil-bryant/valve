import Foundation
import Security

public protocol KeychainStoreProtocol: Sendable
{ func save(key: String, data: Data) throws
  func load(key: String) throws -> Data?
}

public enum KeychainError: Error, LocalizedError, Sendable
{ case unhandled(OSStatus)

  public var errorDescription: String?
  { let description: String
    switch self
    { case .unhandled(let status): description = "Keychain operation failed with status \(status)."
    }
    return description
  }
}

// #R001: Persist arbitrary data to macOS Keychain under service-scoped account key.
// #R005: Load previously persisted data, returning nil when item does not exist.
public struct KeychainStore: KeychainStoreProtocol
{ private let serviceName: String

  public init(serviceName: String = "io.valve.provisioning")
  { self.serviceName = serviceName
  }

  public func save(key: String, data: Data) throws
  { let query: [String: Any] =
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: serviceName,
     kSecAttrAccount as String: key]
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status != errSecSuccess { throw KeychainError.unhandled(status) }
  }

  public func load(key: String) throws -> Data?
  { let query: [String: Any] =
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: serviceName,
     kSecAttrAccount as String: key,
     kSecReturnData as String: true,
     kSecMatchLimit as String: kSecMatchLimitOne]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    let value: Data?
    if status == errSecItemNotFound
    { value = nil
    } else if status == errSecSuccess
    { value = item as? Data
    } else
    { throw KeychainError.unhandled(status)
    }
    return value
  }
}
