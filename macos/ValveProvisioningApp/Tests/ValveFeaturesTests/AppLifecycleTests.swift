import AppKit
import Testing
import ValveFeatures

@Test
func appLifecyclePolicyTerminatesAfterLastWindowClosed() async throws
{ // #R001-T02: AppLifecyclePolicy.terminateAfterLastWindowClosed is true.
  // #R001: App terminates when last window is closed.
  #expect(AppLifecyclePolicy.terminateAfterLastWindowClosed)
}

@Test
@MainActor
func appLifecycleDelegateTerminatesAfterLastWindowClosed() async throws
{ // #R001-T01: ValveAppLifecycleDelegate.applicationShouldTerminateAfterLastWindowClosed returns true.
  // #R001: App terminates when last window is closed.
  let delegate = ValveAppLifecycleDelegate()
  let shouldTerminate = delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
  #expect(shouldTerminate)
}
