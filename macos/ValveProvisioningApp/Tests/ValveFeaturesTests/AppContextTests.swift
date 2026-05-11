import Foundation
import Testing
import ValveFeatures

@Test
func liveContextDefaultsToValvePort8090() async throws
{ let hadValue = getenv("VALVE_BASE_URL") != nil
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
