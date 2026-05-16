import Foundation
import Testing
import ValveNetworking

// #R001-T01: APIError.invalidURL.errorDescription contains "Invalid API URL".
// #R001-T02: APIError.requestFailed(403, "unauthorized").errorDescription contains "403".
// #R001-T03: APIError.transportError("timeout").errorDescription contains "timeout".
// #R001: API error cases covering URL construction, HTTP status, decoding, and transport failures.
@Test
func apiErrorDescriptionsContainExpectedContent()
{ #expect(APIError.invalidURL.errorDescription?.contains("Invalid API URL") == true)
  #expect(APIError.requestFailed(403, "unauthorized").errorDescription?.contains("403") == true)
  #expect(APIError.transportError("timeout").errorDescription?.contains("timeout") == true)
  #expect(APIError.decodingFailed("bad json").errorDescription?.contains("bad json") == true)
}
