import CryptoKit
import Foundation

/// An IAM access key, optionally with the session token that temporary credentials need.
struct AWSCredentials: Sendable {
    let accessKeyID: String
    let secretAccessKey: String
    var sessionToken: String?
}

/// AWS Signature Version 4 request signing (header form), for services other than S3.
enum AWSSigV4 {
    /// Adds `X-Amz-Date`, `X-Amz-Content-Sha256`, the session token (if any), and `Authorization` to `request`.
    /// Sign last: every header already on the request is signed, so changing one afterwards breaks the signature.
    static func sign(_ request: inout URLRequest, credentials: AWSCredentials, region: String, service: String,
                     date: Date = .now) {
        guard let url = request.url, let host = url.host() else { return }
        let (amzDate, dateStamp) = timestamps(for: date)
        let payloadHash = hex(SHA256.hash(data: request.httpBody ?? Data()))

        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-Sha256")
        if let token = credentials.sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        var headers = ["host": url.port.map { "\(host):\($0)" } ?? host]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            headers[name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }
        let signedHeaders = headers.keys.sorted()
        let canonicalRequest = [
            request.httpMethod ?? "GET",
            canonicalURI(url),
            canonicalQuery(url),
            signedHeaders.map { "\($0):\(headers[$0] ?? "")\n" }.joined(),
            signedHeaders.joined(separator: ";"),
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
        ].joined(separator: "\n")

        var key = SymmetricKey(data: Data("AWS4\(credentials.secretAccessKey)".utf8))
        for part in [dateStamp, region, service, "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))

        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(scope), "
                + "SignedHeaders=\(signedHeaders.joined(separator: ";")), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    /// Percent-encodes everything but the unreserved characters, as SigV4 requires. Build request URLs'
    /// paths and queries with this too, so what's sent matches what's signed.
    static func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The already-encoded path with each segment encoded again: non-S3 services sign the double-encoded form
    /// (so a Bedrock model ID's `:` is sent as `%3A` and signed as `%253A`).
    private static func canonicalURI(_ url: URL) -> String {
        let path = url.path(percentEncoded: true)
        guard !path.isEmpty else { return "/" }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encode(String($0)) }
            .joined(separator: "/")
    }

    private static func canonicalQuery(_ url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items
            .map { (encode($0.name), encode($0.value ?? "")) }
            .sorted { $0 < $1 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    /// `yyyyMMdd'T'HHmmss'Z'` and `yyyyMMdd`, in UTC.
    private static func timestamps(for date: Date) -> (amzDate: String, dateStamp: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let dateStamp = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return (dateStamp + String(format: "T%02d%02d%02dZ", c.hour ?? 0, c.minute ?? 0, c.second ?? 0), dateStamp)
    }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
