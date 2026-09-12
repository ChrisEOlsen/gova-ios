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
                // Concurrently, not serially: these are unrelated, and a hung
                // _version (60s default timeout) would otherwise hold session
                // restore — and the whole UI — behind it.
                //
                // restoreSession is what clears auth.isRestoring, so it must run
                // at every launch. Do not drop it.
                async let version: Void = versionGate.check()
                async let session: Void = auth.restoreSession()
                _ = await (version, session)
            }
        }
    }
}
