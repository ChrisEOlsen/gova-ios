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
            .task {
                await versionGate.check()
                // A Keychain token only proves one was saved. Validate it before
                // the app renders signed-in screens.
                await auth.restoreSession()
            }
        }
    }
}
