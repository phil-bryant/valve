import SwiftUI
import ValveFeatures

// #R001: App entry point wires lifecycle delegate and presents root view with live context.
@main
struct ValveProvisioningApp: App
{ @NSApplicationDelegateAdaptor(ValveAppLifecycleDelegate.self) private var lifecycleDelegate

  var body: some Scene
  { WindowGroup("Valve Provisioning")
    { RootView(context: .liveFromEnvironment())
    }
  }
}
