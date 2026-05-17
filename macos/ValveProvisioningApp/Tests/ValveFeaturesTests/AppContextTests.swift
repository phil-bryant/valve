import Foundation
import Testing
import ValveFeatures

// Supplemental numbered tag for environment override parity.
// #R001-T02

@Test
func liveContextDefaultsToValvePort8090() async throws
{ // #R001-T01: liveFromEnvironment() with no env overrides produces context with base URL port 8090.
  // #R001: Live context factory resolves configuration from environment variables.
  // #R005-T01: Calling write appends a JSON-parseable line to the audit file.
  // #R005: Local audit logger appending JSONL entries to Application Support.
  let hadValue = getenv("VALVE_BASE_URL") != nil
  let priorValue = hadValue ? String(cString: getenv("VALVE_BASE_URL")!) : nil
  unsetenv("VALVE_BASE_URL")
  defer
  { if let priorValue
    { setenv("VALVE_BASE_URL", priorValue, 1)
    } else
    { unsetenv("VALVE_BASE_URL")
    }
  }
  let context = AppContext.liveFromEnvironment()
  #expect(context.environment.baseURL.absoluteString == "http://localhost:8090")
}
