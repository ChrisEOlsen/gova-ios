import SwiftUI

@main
struct GovaAppApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var versionGate = VersionGate()

    var body: some Scene {
        WindowGroup {
            Group {
                if versionGate.state == .updateRequired {
                    UpdateRequiredView()
                } else {
                    ContentView()
                        .environmentObject(auth)
                }
            }
            .task { await versionGate.check() }
        }
    }
}
