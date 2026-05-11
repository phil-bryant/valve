import Testing
import ValveFeatures

@Test
func appLifecyclePolicyTerminatesAfterLastWindowClosed() async throws
{ #expect(AppLifecyclePolicy.terminateAfterLastWindowClosed)
}
