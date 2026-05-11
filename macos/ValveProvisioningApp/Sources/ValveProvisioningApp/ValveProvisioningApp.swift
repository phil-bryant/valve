import SwiftUI
import ValveFeatures

@main
struct ValveProvisioningApp: App
{ var body: some Scene
  { WindowGroup("Valve Provisioning")
    { RootView(context: .liveFromEnvironment())
    }
  }
}
