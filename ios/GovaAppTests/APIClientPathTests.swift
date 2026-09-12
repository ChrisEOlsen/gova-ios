import XCTest
@testable import GovaApp

/// `APIClient.path` exists because interpolating a value into a query string
/// corrupts it the moment the value is not an Int. These pin the cases that
/// actually bite against the Go server.
final class APIClientPathTests: XCTestCase {

    func testNoQueryLeavesThePathAlone() {
        XCTAssertEqual(APIClient.path("/api/v1/notes", query: []), "/api/v1/notes")
    }

    func testPlainValuesPassThrough() {
        XCTAssertEqual(
            APIClient.path("/api/v1/notes", query: [
                .init(name: "filter", value: "client_id:42"),
                .init(name: "limit", value: "50"),
            ]),
            "/api/v1/notes?filter=client_id:42&limit=50"
        )
    }

    /// The one that matters most. URLComponents leaves a literal `+` alone, and
    /// Go's net/url decodes `+` in a query as a space — so an unescaped
    /// `a+b@example.com` reaches the handler as `a b@example.com`, matching
    /// nothing. It has to arrive as %2B.
    func testPlusIsEscapedSoGoDoesNotReadItAsASpace() {
        let path = APIClient.path("/api/v1/users", query: [
            .init(name: "filter", value: "email:a+b@example.com"),
        ])
        XCTAssertEqual(path, "/api/v1/users?filter=email:a%2Bb@example.com")
        XCTAssertFalse(path.contains("+"))
    }

    func testSeparatorsAndSpacesAreEscaped() {
        let path = APIClient.path("/api/v1/notes", query: [
            .init(name: "filter", value: "title:tom & jerry"),
        ])
        XCTAssertEqual(path, "/api/v1/notes?filter=title:tom%20%26%20jerry")
    }

    /// A stray `&` or `=` in a value must not be able to introduce a parameter.
    func testAValueCannotInjectAnExtraParameter() {
        let path = APIClient.path("/api/v1/notes", query: [
            .init(name: "filter", value: "title:x&limit=9999"),
        ])
        XCTAssertEqual(path, "/api/v1/notes?filter=title:x%26limit%3D9999")
    }
}
