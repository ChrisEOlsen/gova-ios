import XCTest
@testable import GovaApp

final class VersionGateTests: XCTestCase {

    func testEqualVersions() {
        XCTAssertEqual(compareSemver("1.0.0", "1.0.0"), .orderedSame)
    }

    /// A missing trailing component reads as 0, so a two-part version equals its
    /// three-part spelling.
    func testMissingComponentsAreZero() {
        XCTAssertEqual(compareSemver("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(compareSemver("1", "1.0.0"), .orderedSame)
    }

    /// The case a lexical comparison gets wrong: "1.9" sorts after "1.10" as
    /// text, and before it as a version.
    func testComparisonIsNumericNotLexical() {
        XCTAssertEqual(compareSemver("1.9.0", "1.10.0"), .orderedAscending)
        XCTAssertEqual(compareSemver("1.10.0", "1.9.0"), .orderedDescending)
    }

    func testOrdering() {
        XCTAssertEqual(compareSemver("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(compareSemver("1.0.0", "1.0.1"), .orderedAscending)
    }

    /// A non-numeric component reads as 0 rather than crashing, so a malformed
    /// server response cannot lock a user out of the app.
    func testNonNumericComponentsAreZero() {
        XCTAssertEqual(compareSemver("1.x.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(compareSemver("", "0.0.0"), .orderedSame)
    }
}
