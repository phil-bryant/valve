import Foundation
import ValveDomain

public protocol ValveAPIClientProtocol: Sendable
{ func registerCredential(_ request: RegisterCredentialRequest) async throws -> RegisterCredentialResponse
  func revokeCredential(_ request: RevokeCredentialRequest) async throws -> RevokeCredentialResponse
  func rotateCredential(_ request: RotateCredentialRequest) async throws -> RotateCredentialResponse
  func listCredentials(tenantID: String, installID: String) async throws -> [CredentialRecord]
  func healthCheck() async throws -> Bool
  func readinessCheck() async throws -> Bool
}

public struct ValveAPIClient: ValveAPIClientProtocol
{ public let environment: ValveEnvironment
  public let session: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder

  public init(environment: ValveEnvironment, session: URLSession = .shared)
  { self.environment = environment
    self.session = session
    decoder = JSONDecoder()
    encoder = JSONEncoder()
  }

  public func registerCredential(_ request: RegisterCredentialRequest) async throws -> RegisterCredentialResponse
  { let response: RegisterCredentialResponse = try await send(path: "/v1/valve/credentials/register", method: "POST", body: request)
    return response
  }

  public func revokeCredential(_ request: RevokeCredentialRequest) async throws -> RevokeCredentialResponse
  { let response: RevokeCredentialResponse = try await send(path: "/v1/valve/credentials/revoke", method: "POST", body: request)
    return response
  }

  public func rotateCredential(_ request: RotateCredentialRequest) async throws -> RotateCredentialResponse
  { let response: RotateCredentialResponse = try await send(path: "/v1/valve/credentials/rotate", method: "POST", body: request)
    return response
  }

  public func listCredentials(tenantID: String, installID: String) async throws -> [CredentialRecord]
  { var components = URLComponents(url: environment.baseURL, resolvingAgainstBaseURL: false)
    components?.path = "/v1/valve/credentials"
    components?.queryItems = [URLQueryItem(name: "tenant_id", value: tenantID), URLQueryItem(name: "install_id", value: installID)]
    guard let url = components?.url else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let records: [CredentialRecord]
    do
    { let (data, response) = try await session.data(for: request)
      records = try decodeResponse(data: data, response: response, successType: ListCredentialsResponse.self).credentials
    } catch let error as APIError
    { throw error
    } catch
    { throw APIError.transportError(error.localizedDescription)
    }
    return records
  }

  public func healthCheck() async throws -> Bool
  { let value = try await statusCheck(path: "/healthz")
    return value
  }

  public func readinessCheck() async throws -> Bool
  { let value = try await statusCheck(path: "/readyz")
    return value
  }

  private func statusCheck(path: String) async throws -> Bool
  { let value: Bool
    let url = environment.baseURL.appending(path: path)
    let request = URLRequest(url: url)
    do
    { let (_, response) = try await session.data(for: request)
      value = (response as? HTTPURLResponse)?.statusCode == 200
    } catch
    { throw APIError.transportError(error.localizedDescription)
    }
    return value
  }

  private func send<T: Decodable, U: Encodable>(path: String, method: String, body: U) async throws -> T
  { let url = environment.baseURL.appending(path: path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(body)
    let value: T
    do
    { let (data, response) = try await session.data(for: request)
      value = try decodeResponse(data: data, response: response, successType: T.self)
    } catch let error as APIError
    { throw error
    } catch
    { throw APIError.transportError(error.localizedDescription)
    }
    return value
  }

  private func decodeResponse<T: Decodable>(data: Data, response: URLResponse, successType: T.Type) throws -> T
  { guard let http = response as? HTTPURLResponse else { throw APIError.transportError("Missing HTTP response.") }
    let value: T
    if (200...299).contains(http.statusCode)
    { do
      { value = try decoder.decode(successType, from: data)
      } catch
      { throw APIError.decodingFailed(error.localizedDescription)
      }
    } else
    { let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
      throw APIError.requestFailed(http.statusCode, envelope?.error ?? "Unknown server error")
    }
    return value
  }
}
