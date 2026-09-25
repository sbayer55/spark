import Foundation

/// Decoder for AWS's binary event-stream framing (`application/vnd.amazon.eventstream`), which Bedrock's
/// streaming APIs use instead of SSE.
///
/// Each message is: total length (4 bytes, big-endian), headers length (4), prelude CRC (4), headers,
/// payload, message CRC (4). The CRCs aren't checked: TLS already guarantees the bytes arrived intact.
enum AWSEventStream {
    struct Message {
        /// String-valued headers such as `:message-type`, `:event-type`, and `:exception-type`.
        /// Headers of other types are skipped.
        let headers: [String: String]
        let payload: Data
    }

    struct Parser {
        private var buffer: [UInt8] = []

        mutating func append(_ byte: UInt8) {
            buffer.append(byte)
        }

        /// The next complete message, or nil until more bytes arrive.
        mutating func next() throws -> Message? {
            guard buffer.count >= 12 else { return nil }
            let totalLength = Int(readUInt32(at: 0))
            let headersLength = Int(readUInt32(at: 4))
            guard totalLength >= 16 + headersLength else { throw ProviderError.invalidResponse }
            guard buffer.count >= totalLength else { return nil }

            let headers = try parseHeaders(buffer[12..<(12 + headersLength)])
            let payload = Data(buffer[(12 + headersLength)..<(totalLength - 4)])
            buffer.removeFirst(totalLength)
            return Message(headers: headers, payload: payload)
        }

        private func readUInt32(at offset: Int) -> UInt32 {
            buffer[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
        }

        private func parseHeaders(_ bytes: ArraySlice<UInt8>) throws -> [String: String] {
            var headers: [String: String] = [:]
            var index = bytes.startIndex

            func take(_ count: Int) throws -> ArraySlice<UInt8> {
                guard count >= 0, bytes.endIndex - index >= count else { throw ProviderError.invalidResponse }
                defer { index += count }
                return bytes[index..<(index + count)]
            }
            func length(_ size: Int) throws -> Int {
                try take(size).reduce(0) { $0 << 8 | Int($1) }
            }

            while index < bytes.endIndex {
                let name = String(decoding: try take(length(1)), as: UTF8.self)
                let type = try length(1)
                switch type {
                case 0, 1: break                        // true, false
                case 2: _ = try take(1)                 // byte
                case 3: _ = try take(2)                 // short
                case 4: _ = try take(4)                 // integer
                case 5, 8: _ = try take(8)              // long, timestamp
                case 6: _ = try take(length(2))         // byte array
                case 7: headers[name] = String(decoding: try take(length(2)), as: UTF8.self)
                case 9: _ = try take(16)                // UUID
                default: throw ProviderError.invalidResponse
                }
            }
            return headers
        }
    }
}
