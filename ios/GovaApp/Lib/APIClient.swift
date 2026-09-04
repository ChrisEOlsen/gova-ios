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

/// Talks to the GOVA JSON API. Every response is wrapped in
/// `{"ok":bool,"data":...,"error":"..."}` — see docs/API-CONTRACT.md in the
/// gova-monolith repo. The `T` these methods decode is the payload inside
/// `data`, never the envelope itself.
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL?
    private let configError: String?
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        decoder = JSONDecoder()
        // The API emits RFC3339 with second precision and no fractional part,
        // precisely so this strategy works.
        decoder.dateDecodingStrategy = .iso8601

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

    func get<T: Decodable>(path: String) async throws -> T {
        try await send(path: path, method: "GET")
    }

    func post<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }

    func put<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        try await send(path: path, method: "PUT", body: body)
    }

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
            return try decoder.decode(Envelope<T>.self, from: data).data
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
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
                ?? "Server error \(http.statusCode)"
            throw APIError.server(statusCode: http.statusCode, message: message)
        }
    }
}

private struct ServerError: Decodable { let error: String }
private struct Envelope<T: Decodable>: Decodable { let ok: Bool; let data: T }
