import Foundation
import NotchFlowCore

struct LoopbackHTTPRequest {
    let method: String
    let path: String
    let body: Data
}

enum LoopbackHTTPRequestParseResult {
    case incomplete
    case request(LoopbackHTTPRequest)
    case rejected(LoopbackListenerRejection)
}

struct LoopbackHTTPRequestParser {
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let maximumHeaderByteCount = 16_384

    private var bytes = Data()

    mutating func append(_ data: Data) -> LoopbackHTTPRequestParseResult {
        bytes.append(data)

        guard let headerRange = bytes.range(of: Self.headerTerminator) else {
            return bytes.count > Self.maximumHeaderByteCount
                ? .rejected(.payloadTooLarge)
                : .incomplete
        }
        guard headerRange.lowerBound <= Self.maximumHeaderByteCount else {
            return .rejected(.payloadTooLarge)
        }

        let headerData = bytes[..<headerRange.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else {
            return .rejected(.invalidPayload)
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .rejected(.invalidPayload)
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[2].hasPrefix("HTTP/1.") else {
            return .rejected(.invalidPayload)
        }

        var contentLength: Int?
        for line in lines.dropFirst() {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2 else {
                return .rejected(.invalidPayload)
            }
            if fields[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                guard contentLength == nil,
                      let parsedLength = Int(fields[1].trimmingCharacters(in: .whitespaces)),
                      parsedLength >= 0 else {
                    return .rejected(.invalidPayload)
                }
                contentLength = parsedLength
            }
        }

        guard let contentLength else {
            return .rejected(.invalidPayload)
        }
        guard contentLength <= IPCMessageValidator.maximumPayloadByteCount else {
            return .rejected(.payloadTooLarge)
        }

        let bodyStart = headerRange.upperBound
        guard bytes.count >= bodyStart + contentLength else {
            return .incomplete
        }
        let body = bytes[bodyStart..<(bodyStart + contentLength)]
        return .request(
            LoopbackHTTPRequest(
                method: String(requestParts[0]),
                path: String(requestParts[1]),
                body: Data(body)
            )
        )
    }
}
