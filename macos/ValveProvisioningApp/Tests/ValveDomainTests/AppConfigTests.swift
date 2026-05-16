import Foundation
import Testing
import ValveDomain

// #R001-T01: Two ValveEnvironment instances with identical fields are equal.
// #R001-T02: Two instances with different baseURL values are not equal.
// #R001: Value-type environment configuration with base URL, tenant, install, and actor identity.
@Test
func valveEnvironmentEqualityReflectsFieldValues()
{ let url1 = URL(string: "http://localhost:8090")!
  let url2 = URL(string: "http://localhost:9090")!
  let env1 = ValveEnvironment(baseURL: url1, tenantID: "t", installID: "i", actorUserID: "a")
  let env2 = ValveEnvironment(baseURL: url1, tenantID: "t", installID: "i", actorUserID: "a")
  let env3 = ValveEnvironment(baseURL: url2, tenantID: "t", installID: "i", actorUserID: "a")
  #expect(env1 == env2)
  #expect(env1 != env3)
}
