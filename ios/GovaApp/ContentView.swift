import SwiftUI

// Root navigation shell.
// /build replaces the placeholder body with NavigationStack destinations
// for each screen generated from SEED.md.
struct ContentView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        NavigationStack {
            Text("Run /build to generate your app screens.")
                .foregroundStyle(.secondary)
                .navigationTitle("GOVA iOS")
        }
    }
}
