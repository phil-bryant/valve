import AppKit

// #R001: App terminates when last window is closed so launcher scripts return to terminal prompt.
public enum AppLifecyclePolicy
{ public static let terminateAfterLastWindowClosed = true
}

public final class ValveAppLifecycleDelegate: NSObject, NSApplicationDelegate
{ public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
  { let value = AppLifecyclePolicy.terminateAfterLastWindowClosed
    return value
  }
}
