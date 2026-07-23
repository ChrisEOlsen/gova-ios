import SwiftUI

/// Full-screen blocking view shown when the app build is older than the server's
/// minimum supported client version. Deliberately has no dismiss action.
struct UpdateRequiredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Update Required")
                .font(.title2).bold()
            Text("A newer version of this app is required to continue. Please update to the latest version.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
