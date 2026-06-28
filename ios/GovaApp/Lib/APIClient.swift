import Foundation

enum APIError: LocalizedError {
    case network(Error)
    case decode(Error)
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .network(let e): return e.localizedDescription
        case .decode(let e): return "Response format error: \(e.localizedDescription)"
        case .server(_, let msg): return msg
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let decoder: JSONDecoder

    private init() {
        guard
            let configURL = Bundle.main.url(forResource: "Config", withExtension: "plist"),
            let config = NSDictionary(contentsOf: configURL),
            let url = config["API_BASE_URL"] as? String
        else {
            fatalError("Config.plist missing or API_BASE_URL not set — run install-claude.sh")
        }
        baseURL = url
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            fatalError("Invalid URL: \(baseURL + path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthManager.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    func get<T: Decodable>(path: String) async throws -> T {
        let request = makeRequest(path: path, method: "GET")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return try handle(data: data, response: response)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func post<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        let bodyData = try JSONEncoder().encode(body)
        let request = makeRequest(path: path, method: "POST", body: bodyData)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return try handle(data: data, response: response)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func delete(path: String) async throws {
        let request = makeRequest(path: path, method: "DELETE")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let _: EmptyResponse = try handle(data: data, response: response)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func handle<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
                ?? "Server error \(http.statusCode)"
            throw APIError.server(statusCode: http.statusCode, message: msg)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decode(error)
        }
    }
}

private struct ServerError: Decodable { let error: String }
private struct EmptyResponse: Decodable {}
