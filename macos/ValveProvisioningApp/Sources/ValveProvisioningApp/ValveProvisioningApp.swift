import SwiftUI
import ValveFeatures

@main
struct ValveProvisioningApp: App
{ @NSApplicationDelegateAdaptor(ValveAppLifecycleDelegate.self) private var lifecycleDelegate

  var body: some Scene
  { WindowGroup("Valve Provisioning")
    { RootView(context: .liveFromEnvironment())
    }
  }
}
