import Foundation

/// Compares two dotted numeric version strings. Missing trailing components are
/// treated as 0, so "1.2" == "1.2.0"; comparison is numeric, so "1.9" < "1.10".
/// Non-numeric components are treated as 0. Covered by VersionGateTests.
func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(pa.count, pb.count)
    for i in 0..<count {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
}

@MainActor
final class VersionGate: ObservableObject {
    enum State: Equatable { case checking, ok, updateRequired }

    @Published private(set) var state: State = .checking

    private struct VersionInfo: Decodable {
        let apiVersion: String
        let minClientVersion: String
        enum CodingKeys: String, CodingKey {
            case apiVersion = "api_version"
            case minClientVersion = "min_client_version"
        }
    }

    /// Checks the server's minimum supported client version against this build.
    /// FAILS OPEN: any error, unreachable endpoint, or missing version leaves the
    /// app usable. Only a provably-too-old client is blocked.
    func check() async {
        do {
            let info: VersionInfo = try await APIClient.shared.get(path: "/api/v1/_version")
            let client = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            if !client.isEmpty,
               compareSemver(client, info.minClientVersion) == .orderedAscending {
                state = .updateRequired
            } else {
                state = .ok
            }
        } catch {
            state = .ok  // fail open
        }
    }
}
