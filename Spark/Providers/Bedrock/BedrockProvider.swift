import Foundation

/// Models on Amazon Bedrock, through the model-agnostic Converse API (`POST /model/{id}/converse-stream`).
/// Signs requests with a Bedrock API key (bearer token) or an IAM access key (SigV4).
/// Only offered once credentials are set in Settings (see `BedrockSettings`).
struct BedrockProvider: LLMProvider {
    enum Credentials: Sendable {
        case apiKey(String)
        case accessKeys(AWSCredentials)
    }

    static let providerID = "bedrock"
    /// SigV4 signs both the control plane (`bedrock.`) and runtime (`bedrock-runtime.`) as this service.
    private static let signingService = "bedrock"

    let id = BedrockProvider.providerID
    let displayName = "Amazon Bedrock"
    /// e.g. `us-east-1`.
    let region: String
    let credentials: Credentials
    var session: URLSession = .shared

    private var controlURL: URL? { endpoint("bedrock") }
    private var runtimeURL: URL? { endpoint("bedrock-runtime") }

    /// `https://<service>.<region>.amazonaws.com`, or nil if the region could put anything but a
    /// DNS label there (credentials must never go to another host).
    private func endpoint(_ service: String) -> URL? {
        guard !region.isEmpty, region.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") })
        else { return nil }
        return URL(string: "https://\(service).\(region).amazonaws.com")
    }

    /// Cross-region inference profiles (e.g. `us.anthropic.claude-…`, which newer models require), then
    /// streaming text models invokable on demand. Either list alone is enough if the other is denied.
    func availableModels() async throws -> [String] {
        async let profiles = Self.result { try await inferenceProfiles() }
        async let foundation = Self.result { try await onDemandModels() }
        switch (await profiles, await foundation) {
        case (.failure(let error), .failure):
            throw error
        case (let profiles, let foundation):
            let ids = ((try? profiles.get()) ?? []) + ((try? foundation.get()) ?? [])
            var seen = Set<String>()
            return ids.filter { seen.insert($0).inserted }
        }
    }

    func stream(messages: [ChatMessage], model: String) -> AsyncThrowingStream<String, Error> {
        let transcript = AlternatingTranscript(messages)
        let body = ConverseRequest(
            messages: transcript.turns.map {
                ConverseRequest.Message(role: $0.role.rawValue, content: [ConverseRequest.Block(text: $0.text)])
            },
            system: transcript.system.map { [ConverseRequest.Block(text: $0)] },
            // Claude requires a cap; other models' defaults are fine.
            inferenceConfig: model.contains("anthropic.claude")
                ? ConverseRequest.InferenceConfig(maxTokens: AnthropicProvider.maxOutputTokens(for: model)) : nil
        )
        let request: URLRequest
        do {
            var draft = try makeRequest(
                base: runtimeURL,
                path: "/model/\(AWSSigV4.encode(model))/converse-stream",
                method: "POST",
                body: try JSONEncoder().encode(body),
                timeout: 300
            )
            draft.setValue("application/vnd.amazon.eventstream", forHTTPHeaderField: "Accept")
            request = authorized(draft)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try await ProviderHTTP.validate(response, bytes: bytes)

                    var parser = AWSEventStream.Parser()
                    let decoder = JSONDecoder()
                    for try await byte in bytes {
                        parser.append(byte)
                        while let message = try parser.next() {
                            if let text = try Self.text(in: message, decoder: decoder), !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapError(error, url: request.url))
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// The reply text in a ConverseStream message; throws for exceptions and errors.
    private static func text(in message: AWSEventStream.Message, decoder: JSONDecoder) throws -> String? {
        switch message.headers[":message-type"] {
        case "event":
            guard message.headers[":event-type"] == "contentBlockDelta" else { return nil }
            return try decoder.decode(ContentBlockDelta.self, from: message.payload).delta.text
        case "exception":
            let detail = ProviderHTTP.errorMessage(in: message.payload)
            throw ProviderError.server(detail ?? message.headers[":exception-type"] ?? "Bedrock reported an error.")
        case "error":
            throw ProviderError.server(message.headers[":error-message"] ?? message.headers[":error-code"]
                                       ?? "Bedrock reported an error.")
        default:
            return nil
        }
    }

    // MARK: - Model lists

    private func inferenceProfiles() async throws -> [String] {
        var ids: [String] = []
        var nextToken: String?
        repeat {
            var query = [("type", "SYSTEM_DEFINED"), ("maxResults", "1000")]
            if let nextToken { query.append(("nextToken", nextToken)) }
            let page: InferenceProfileList = try await get("/inference-profiles", query: query)
            ids += page.inferenceProfileSummaries.filter { $0.status == "ACTIVE" }.map(\.inferenceProfileId)
            nextToken = page.nextToken
        } while nextToken != nil
        return ids.sorted()
    }

    private func onDemandModels() async throws -> [String] {
        let list: FoundationModelList = try await get("/foundation-models", query: [("byOutputModality", "TEXT")])
        return list.modelSummaries
            .filter { model in
                model.inferenceTypesSupported?.contains("ON_DEMAND") == true
                    && model.responseStreamingSupported == true
                    && model.inputModalities?.contains("TEXT") == true
                    && model.modelLifecycle?.status != "LEGACY"
            }
            .map(\.modelId)
            .sorted()
    }

    private static func result<T>(_ body: () async throws -> T) async -> Result<T, any Error> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }

    private func get<Response: Decodable>(_ path: String, query: [(String, String)]) async throws -> Response {
        let request = authorized(try makeRequest(base: controlURL, path: path, query: query, method: "GET",
                                                 body: nil, timeout: 10))
        do {
            let (data, response) = try await session.data(for: request)
            try ProviderHTTP.validate(response, body: data)
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw mapError(error, url: request.url)
        }
    }

    // MARK: - Helpers

    /// `path` must already be percent-encoded; query items are encoded here the way SigV4 expects.
    private func makeRequest(base: URL?, path: String, query: [(String, String)] = [], method: String,
                             body: Data?, timeout: TimeInterval) throws -> URLRequest {
        guard let base, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw ProviderError.server("“\(region)” isn't a valid AWS region. Check the Bedrock region in Settings.")
        }
        components.percentEncodedPath = path
        if !query.isEmpty {
            components.percentEncodedQueryItems = query.map {
                URLQueryItem(name: AWSSigV4.encode($0.0), value: AWSSigV4.encode($0.1))
            }
        }
        guard let url = components.url else { throw ProviderError.invalidResponse }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        switch credentials {
        case .apiKey(let key):
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .accessKeys(let credentials):
            AWSSigV4.sign(&request, credentials: credentials, region: region, service: Self.signingService)
        }
        return request
    }

    private func mapError(_ error: any Error, url: URL?) -> any Error {
        ProviderHTTP.mapError(error, provider: displayName, url: url,
                              fallbackURL: runtimeURL ?? URL(string: "https://aws.amazon.com")!)
    }
}

// MARK: - Wire types

private struct ConverseRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [Block]
    }

    struct Block: Encodable {
        let text: String
    }

    struct InferenceConfig: Encodable {
        let maxTokens: Int
    }

    let messages: [Message]
    let system: [Block]?
    let inferenceConfig: InferenceConfig?
}

private struct ContentBlockDelta: Decodable {
    /// Text for text deltas; reasoning and tool-use deltas have none.
    struct Delta: Decodable { let text: String? }
    let delta: Delta
}

private struct InferenceProfileList: Decodable {
    struct Summary: Decodable {
        let inferenceProfileId: String
        let status: String?
    }

    let inferenceProfileSummaries: [Summary]
    let nextToken: String?
}

private struct FoundationModelList: Decodable {
    struct Summary: Decodable {
        struct Lifecycle: Decodable { let status: String? }

        let modelId: String
        let inputModalities: [String]?
        let inferenceTypesSupported: [String]?
        let responseStreamingSupported: Bool?
        let modelLifecycle: Lifecycle?
    }

    let modelSummaries: [FoundationModelList.Summary]
}
