import Testing
import ValveFeatures

@Test
func appLifecyclePolicyTerminatesAfterLastWindowClosed() async throws
{ // #R001-T01: ValveAppLifecycleDelegate.applicationShouldTerminateAfterLastWindowClosed returns true.
  // #R001-T02: AppLifecyclePolicy.terminateAfterLastWindowClosed is true.
  // #R001: App terminates when last window is closed.
  #expect(AppLifecyclePolicy.terminateAfterLastWindowClosed)
}
