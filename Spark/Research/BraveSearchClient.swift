import Foundation

/// Web search via the Brave Search API (`GET /res/v1/web/search`).
struct BraveSearchClient: Sendable {
    struct Result: Hashable, Sendable {
        let title: String
        let url: URL
        let description: String
    }

    let apiKey: String
    var session: URLSession = .shared
    /// Results per query (Brave allows up to 20).
    var count = 5
    /// Overridable so the pipeline can be exercised against a local stand-in.
    var endpoint = URL(string: "https://api.search.brave.com/res/v1/web/search")!

    func search(_ query: String) async throws -> [Result] {
        guard !apiKey.isEmpty else { throw ResearchError.missingAPIKey }
        let request = makeRequest(query: query)
        do {
            return try await perform(request, retryOnRateLimit: true)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ResearchError.searchFailed(error.localizedDescription)
        }
    }

    private func perform(_ request: URLRequest, retryOnRateLimit: Bool) async throws -> [Result] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ResearchError.searchFailed("Invalid response.") }
        switch http.statusCode {
        case 200..<300:
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return (decoded.web?.results ?? []).compactMap { item in
                guard let url = URL(string: item.url) else { return nil }
                return Result(title: item.title, url: url, description: item.description ?? "")
            }
        case 401, 403:
            throw ResearchError.searchRejected(status: http.statusCode)
        case 429:
            guard retryOnRateLimit else { throw ResearchError.searchRateLimited }
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
            try await Task.sleep(for: .seconds(min(retryAfter, 5)))
            return try await perform(request, retryOnRateLimit: false)
        default:
            throw ResearchError.searchFailed("Brave Search returned HTTP \(http.statusCode).")
        }
    }

    private func makeRequest(query: String) -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "text_decorations", value: "false"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        return request
    }
}

/// Errors surfaced to the user from the research pipeline.
enum ResearchError: LocalizedError {
    case missingAPIKey
    case searchRejected(status: Int)
    case searchRateLimited
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Brave Search API key in Settings to use Research."
        case .searchRejected:
            "Brave Search rejected the API key. Check it in Settings."
        case .searchRateLimited:
            "Brave Search rate limit reached. Try again in a moment."
        case .searchFailed(let reason):
            "Web search failed: \(reason)"
        }
    }
}

// MARK: - Wire types

private struct SearchResponse: Decodable {
    struct Web: Decodable {
        let results: [Item]
    }

    struct Item: Decodable {
        let title: String
        let url: String
        let description: String?
    }

    let web: Web?
}
