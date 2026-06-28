import SwiftUI

@main
struct GovaAppApp: App {
    @ObservedObject private var auth = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}
