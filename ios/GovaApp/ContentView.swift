import SwiftUI

// Root navigation shell.
// /build replaces the placeholder body with NavigationStack destinations
// for each screen generated from SEED.md.
struct ContentView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        // The gate order is fixed, and /build keeps it: restoring first, then
        // the login gate, then the app. Checking isLoggedIn first would render
        // the app on the strength of a Keychain token that has not been
        // validated yet — a flash of screens whose every request then 401s.
        if auth.isRestoring {
            ProgressView()
                .controlSize(.large)
                .accessibilityIdentifier("restoringSession")
        } else {
            NavigationStack {
                Text("Run /build to generate your app screens.")
                    .foregroundStyle(.secondary)
                    .navigationTitle("GOVA iOS")
            }
        }
    }
}
