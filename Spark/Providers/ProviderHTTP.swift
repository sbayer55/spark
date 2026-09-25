import Foundation

/// HTTP plumbing shared by the network-backed providers.
enum ProviderHTTP {
    /// Throws `ProviderError.http` for a non-2xx response.
    static func validate(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(status: http.statusCode, message: errorMessage(in: body))
        }
    }

    /// For streamed requests: reads a non-2xx response's body (up to 64 KB) and throws `ProviderError.http`.
    static func validate(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard !(200..<300).contains(http.statusCode) else { return }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count > 64_000 { break }
        }
        throw ProviderError.http(status: http.statusCode, message: errorMessage(in: body))
    }

    /// Extracts the message from the error bodies Spark's providers send: `{"error": {"message": …}}`
    /// (OpenAI, Anthropic), `{"error": "…"}`, or `{"message": …}` (AWS). Falls back to the raw text.
    static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let error = object["error"] as? [String: Any] { return error["message"] as? String }
        if let error = object["error"] as? String { return error }
        return (object["message"] ?? object["Message"]) as? String
    }

    /// Turns connection failures into `ProviderError.unreachable` (naming `fallbackURL`'s origin when the
    /// request URL is unknown) and URL cancellation into `CancellationError`.
    static func mapError(_ error: any Error, provider: String, url: URL?, fallbackURL: URL) -> any Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            let root = url.flatMap(origin) ?? fallbackURL
            return ProviderError.unreachable(provider: provider, url: root)
        default:
            return urlError
        }
    }

    /// `scheme://host[:port]` of a URL, for user-facing messages.
    private static func origin(of url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host()
        components.port = url.port
        return components.url
    }
}
