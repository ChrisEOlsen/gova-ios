import Foundation

enum APIError: LocalizedError {
    case configuration(String)
    case network(Error)
    case decode(Error)
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .configuration(let msg): return msg
        case .network(let e): return e.localizedDescription
        case .decode(let e): return "Response format error: \(e.localizedDescription)"
        case .server(_, let msg): return msg
        }
    }
}

/// Thrown inside `.decode` when a response the caller asked to decode carried no
/// `data`. The server omits `data` entirely for an empty payload (`jsonOK(w,
/// nil)` → `{"ok":true}`), which is legal — it means the caller should have used
/// a discarding overload.
struct MissingPayload: LocalizedError {
    let path: String
    var errorDescription: String? {
        "\(path) answered with no data — call the discarding overload for this endpoint."
    }
}

/// `meta` from a list response. See docs/API-CONTRACT.md § Pagination.
struct PageMeta: Decodable {
    let limit: Int
    let offset: Int
    let total: Int
}

/// One window of a list endpoint: the rows, plus the `meta` that says whether
/// more exist.
struct Page<Item: Decodable> {
    let items: [Item]
    let meta: PageMeta?

    /// True when the server holds rows past this window.
    var hasMore: Bool {
        guard let meta else { return false }
        return meta.offset + items.count < meta.total
    }
}

/// Talks to the GOVA JSON API. Every response is wrapped in
/// `{"ok":bool,"data":...,"meta":...,"error":"..."}` — see docs/API-CONTRACT.md
/// in the gova-monolith repo. The `T` these methods decode is the payload inside
/// `data`, never the envelope itself.
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL?
    private let configError: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeCookielessSession()

        decoder = JSONDecoder()
        // The API emits RFC3339 with second precision and no fractional part,
        // precisely so this strategy works.
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        // The mirror image: models.Time on the server parses strict RFC3339 with
        // seconds and a zone. Without this a Date in a request body encodes as a
        // seconds-since-2001 number and the server answers 400.
        encoder.dateEncodingStrategy = .iso8601

        guard
            let configURL = Bundle.main.url(forResource: "Config", withExtension: "plist"),
            let config = NSDictionary(contentsOf: configURL),
            let raw = config["API_BASE_URL"] as? String
        else {
            baseURL = nil
            configError = "Config.plist is missing or has no API_BASE_URL — run install-claude.sh"
            return
        }
        guard let url = URL(string: raw) else {
            baseURL = nil
            configError = "API_BASE_URL is not a valid URL: \(raw)"
            return
        }
        baseURL = url
        configError = nil
    }

    /// A session that can neither store nor send cookies.
    ///
    /// This is load-bearing, not hygiene. The server's CSRF middleware exempts
    /// bearer requests, and `login_token` is by definition the one call that has
    /// no bearer token yet — so its exemption rests entirely on the premise that
    /// "a native client holds no cookies at all" (gova-monolith
    /// middleware/csrf.go). `URLSession.shared` breaks that premise: the launch
    /// `GET /api/v1/_version` is a safe method, so the server mints a
    /// `csrf_token` cookie, the shared jar stores it, and the next login POST
    /// replays it. The server then sees a cookie-carrying unsafe request with no
    /// `X-CSRF-Token` and answers 403 — every login, on every fresh install.
    /// gova-monolith's own csrf_test.go pins that 403.
    ///
    /// Registering makes it worse: `register` sets a `gova_session` cookie, and
    /// `middleware.Auth` resolves cookies before bearer tokens, so the app would
    /// silently authenticate by ambient cookie instead of by the token this whole
    /// template is built on.
    private static func makeCookielessSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }

    /// Builds a path with a properly percent-encoded query string.
    ///
    /// Interpolating values into a query (`"?filter=name:\(text)"`) is fine for
    /// the generated int-keyed cases and silently corrupts the URL for anything
    /// else — an email's `+`, a space, an `&` in free text. Use this instead.
    ///
    ///     APIClient.path("/api/v1/notes", query: [
    ///         .init(name: "filter", value: "author:\(email)"),
    ///         .init(name: "limit", value: "50"),
    ///     ])
    static func path(_ base: String, query: [URLQueryItem]) -> String {
        guard !query.isEmpty else { return base }
        var components = URLComponents()
        components.path = base
        components.queryItems = query
        // URLComponents leaves a literal `+` as-is, and Go's net/url decodes `+`
        // in a query as a space — so `a+b@example.com` would reach a handler as
        // `a b@example.com`. Spaces are already `%20` here, never `+`, so every
        // remaining `+` is a literal that has to be escaped.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.string ?? base
    }

    // MARK: - GET

    func get<T: Decodable>(path: String) async throws -> T {
        try await send(path: path, method: "GET")
    }

    /// Fetches one window of a list endpoint, keeping the `meta` that `get`
    /// discards. Lists default to 50 rows, so a list that can grow past that
    /// must page: pass `?limit=&offset=` and append while `hasMore`.
    func getPage<Item: Decodable>(path: String) async throws -> Page<Item> {
        let data = try await sendForData(path: path, method: "GET", body: Optional<Never>.none)
        do {
            let envelope = try decoder.decode(ListEnvelope<Item>.self, from: data)
            return Page(items: envelope.data ?? [], meta: envelope.meta)
        } catch {
            throw APIError.decode(error)
        }
    }

    // MARK: - POST

    func post<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }

    /// Posts and discards the response payload — for an endpoint whose response
    /// is `empty`, or a scaffolded `gova handler` that still answers `{"ok":true}`.
    func post(path: String, body: some Encodable) async throws {
        _ = try await sendForData(path: path, method: "POST", body: body)
    }

    /// Posts with no request body, decoding the response.
    func post<T: Decodable>(path: String) async throws -> T {
        try await send(path: path, method: "POST")
    }

    /// Posts with no request body, discarding the response — the shape a
    /// `control: button` custom endpoint usually takes.
    func post(path: String) async throws {
        _ = try await sendForData(path: path, method: "POST", body: Optional<Never>.none)
    }

    // MARK: - PUT

    func put<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        try await send(path: path, method: "PUT", body: body)
    }

    /// Puts and discards the response payload.
    func put(path: String, body: some Encodable) async throws {
        _ = try await sendForData(path: path, method: "PUT", body: body)
    }

    // MARK: - DELETE

    /// Deletes and decodes the response payload, for an endpoint that returns one.
    func delete<T: Decodable>(path: String) async throws -> T {
        try await send(path: path, method: "DELETE")
    }

    /// Deletes and discards the response payload.
    func delete(path: String) async throws {
        _ = try await sendForData(path: path, method: "DELETE", body: Optional<Never>.none)
    }

    // MARK: - One request path

    private func send<T: Decodable>(
        path: String, method: String, body: (some Encodable)? = Optional<Never>.none
    ) async throws -> T {
        let data = try await sendForData(path: path, method: method, body: body)
        do {
            guard let payload = try decoder.decode(Envelope<T>.self, from: data).data else {
                throw MissingPayload(path: path)
            }
            return payload
        } catch {
            throw APIError.decode(error)
        }
    }

    private func sendForData(
        path: String, method: String, body: (some Encodable)?
    ) async throws -> Data {
        let request = try makeRequest(path: path, method: method, body: body)
        do {
            let (data, response) = try await session.data(for: request)
            try validate(data: data, response: response)
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func makeRequest(
        path: String, method: String, body: (some Encodable)?
    ) throws -> URLRequest {
        guard let baseURL else {
            throw APIError.configuration(configError ?? "API client is not configured")
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.configuration("Invalid request path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthManager.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            // A 401 while holding a token means that token is dead — bearer
            // tokens expire after 30 days, and logout_all retires them early.
            // Without this the app keeps rendering signed-in screens whose every
            // request fails, and the isLoggedIn gate never returns to login.
            if http.statusCode == 401, AuthManager.shared.token != nil {
                Task { @MainActor in AuthManager.shared.logout() }
            }
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
                ?? "Server error \(http.statusCode)"
            throw APIError.server(statusCode: http.statusCode, message: message)
        }
    }
}

private struct ServerError: Decodable { let error: String }

// `data` is optional because the server omits it for an empty payload; the
// decoding paths turn a missing payload into a named error.
private struct Envelope<T: Decodable>: Decodable { let ok: Bool; let data: T? }
private struct ListEnvelope<Item: Decodable>: Decodable {
    let ok: Bool
    let data: [Item]?
    let meta: PageMeta?
}
