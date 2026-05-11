import Foundation

public struct ValveEnvironment: Equatable, Sendable
{ public let baseURL: URL
  public let tenantID: String
  public let installID: String
  public let actorUserID: String

  public init(baseURL: URL, tenantID: String, installID: String, actorUserID: String)
  { self.baseURL = baseURL
    self.tenantID = tenantID
    self.installID = installID
    self.actorUserID = actorUserID
  }
}
