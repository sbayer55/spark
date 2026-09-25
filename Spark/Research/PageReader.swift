import Foundation
import SwiftSoup

/// Downloads a web page and reduces it to readable text for the model.
/// This is the only file that may `import SwiftSoup`.
struct PageReader: Sendable {
    enum PageError: LocalizedError {
        case notHTML
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notHTML: "Not an HTML page"
            case .http(let status): "HTTP \(status)"
            }
        }
    }

    var session: URLSession = PageReader.makeSession()
    /// Stop downloading after this many bytes; the rest of the page is ignored.
    var maxBytes = 1_000_000
    /// Truncate extracted text to this many characters.
    var maxCharacters = 3_000

    /// Fetches `url` and returns its readable body text, truncated to `maxCharacters`.
    func readableText(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Spark/0.1 (macOS; research)", forHTTPHeaderField: "User-Agent")

        let html: String
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw PageError.notHTML }
            guard (200..<300).contains(http.statusCode) else { throw PageError.http(http.statusCode) }
            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard type.isEmpty || type.contains("text/html") || type.contains("application/xhtml") else {
                throw PageError.notHTML
            }

            var data = Data()
            data.reserveCapacity(min(maxBytes, 256_000))
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
            html = String(decoding: data, as: UTF8.self)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        return try Self.extractText(html: html, baseURL: url, maxCharacters: maxCharacters)
    }

    /// Rewrites `http://` to `https://` (ATS blocks plain HTTP off the local network) and drops
    /// URLs that can't be read as HTML.
    static func fetchableURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host != nil
        else { return nil }
        let binaryExtensions: Set<String> = ["pdf", "zip", "gz", "dmg", "pkg", "png", "jpg", "jpeg", "gif", "webp", "svg", "mp4", "mp3"]
        if binaryExtensions.contains(url.pathExtension.lowercased()) { return nil }
        components.scheme = "https"
        components.fragment = nil
        return components.url
    }

    /// Readable text from an HTML document: main content with chrome and scripts removed, whitespace collapsed.
    static func extractText(html: String, baseURL: URL, maxCharacters: Int) throws -> String {
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        try document.select("script, style, noscript, nav, header, footer, aside, form, iframe, svg, template").remove()
        let container = try document.select("article").first()
            ?? document.select("main").first()
            ?? document.body()
        let raw = try container?.text() ?? ""
        let collapsed = raw
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(maxCharacters))
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }
}
