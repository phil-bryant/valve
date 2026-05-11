import Foundation
import Testing
import ValveDomain
import ValveNetworking

private final class URLProtocolStub: URLProtocol, @unchecked Sendable
{ nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool
  { let value = true
    return value
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest
  { let value = request
    return value
  }

  override func startLoading()
  { if let handler = URLProtocolStub.handler
    { do
      { let (response, data) = try handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      } catch
      { client?.urlProtocol(self, didFailWithError: error)
      }
    } else
    { client?.urlProtocol(self, didFailWithError: APIError.transportError("No URLProtocolStub handler"))
    }
  }

  override func stopLoading()
  { }
}

@Suite(.serialized)
struct ValveAPIClientTests
{ @Test
  func listCredentialsDecodesResponse() async throws
  { let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: config)
    let env = ValveEnvironment(
      baseURL: URL(string: "http://localhost:8080")!,
      tenantID: "tenantA",
      installID: "installA",
      actorUserID: "actorA"
    )
    URLProtocolStub.handler =
    { request in
      #expect(request.url?.path == "/v1/valve/credentials")
      let body = """
      {"credentials":[{"credential_id":"cred_1","tenant_id":"tenantA","install_id":"installA","device_label":"MacBook","app_bundle_id":"io.valve.piston","app_version":"1.0.0","app_build":"100","platform":"macOS","status":"active","created_at":"2026-05-11T00:00:00Z","revoked_at":null}]}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      let value = (response, body)
      return value
    }
    let client = ValveAPIClient(environment: env, session: session)
    let records = try await client.listCredentials(tenantID: "tenantA", installID: "installA")
    #expect(records.count == 1)
    #expect(records.first?.credentialID == "cred_1")
  }

  @Test
  func listCredentialsMapsServerErrorEnvelope() async throws
  { let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: config)
    let env = ValveEnvironment(
      baseURL: URL(string: "http://localhost:8080")!,
      tenantID: "tenantA",
      installID: "installA",
      actorUserID: "actorA"
    )
    URLProtocolStub.handler =
    { request in
      let body = #"{"error":"unauthorized"}"#.data(using: .utf8)!
      let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
      let value = (response, body)
      return value
    }
    let client = ValveAPIClient(environment: env, session: session)
    do
    { _ = try await client.listCredentials(tenantID: "tenantA", installID: "installA")
      Issue.record("Expected listCredentials to throw APIError.requestFailed")
    } catch let error as APIError
    { switch error
      { case .requestFailed(let code, let message):
          #expect(code == 401)
          #expect(message == "unauthorized")
        default:
          Issue.record("Unexpected APIError: \(error.localizedDescription)")
      }
    }
  }
}
