import Foundation

// #R001: API error cases covering URL construction, HTTP status, decoding, and transport failures.
public enum APIError: Error, LocalizedError, Sendable
{ case invalidURL
  case requestFailed(Int, String)
  case decodingFailed(String)
  case transportError(String)

  public var errorDescription: String?
  { let description: String
    switch self
    { case .invalidURL: description = "Invalid API URL."
      case .requestFailed(let statusCode, let message): description = "Request failed (\(statusCode)): \(message)"
      case .decodingFailed(let message): description = "Decoding failed: \(message)"
      case .transportError(let message): description = "Network error: \(message)"
    }
    return description
  }
}
