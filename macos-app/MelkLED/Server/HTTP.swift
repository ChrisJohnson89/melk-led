//
//  HTTP.swift
//  MelkLED
//
//  Minimal HTTP/1.1 request parsing and response building for ControlServer.
//  Only what a tiny local JSON control endpoint needs — no keep-alive, no
//  chunked encoding.
//

import Foundation

/// A parsed HTTP request. `init?` returns nil until the full request
/// (headers + Content-Length body) has arrived in the buffer.
struct HTTPRequest {
    let method: String
    let path: String
    let body: [String: Any]

    init?(raw: Data) {
        guard let headerEnd = HTTPRequest.range(of: "\r\n\r\n", in: raw) else { return nil }
        let headerData = raw.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        self.method = String(parts[0]).uppercased()
        // Strip any query string.
        self.path = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])

        // Content-Length gates body completeness.
        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let available = raw.count - bodyStart
        if available < contentLength { return nil } // wait for more bytes

        if contentLength > 0 {
            let bodyData = raw.subdata(in: bodyStart..<(bodyStart + contentLength))
            self.body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
        } else {
            self.body = [:]
        }
    }

    func string(_ key: String) -> String? {
        if let s = body[key] as? String { return s }
        if let n = body[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = body[key] as? Int { return n }
        if let n = body[key] as? NSNumber { return n.intValue }
        if let s = body[key] as? String { return Int(s) }
        return nil
    }

    private static func range(of marker: String, in data: Data) -> Range<Int>? {
        guard let markerData = marker.data(using: .utf8), !markerData.isEmpty else { return nil }
        guard let found = data.range(of: markerData) else { return nil }
        return found.lowerBound..<found.upperBound
    }
}

struct HTTPResponse {
    let status: Int
    let payload: [String: Any]

    static func json(_ payload: [String: Any], status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, payload: payload)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        HTTPResponse(status: status, payload: ["ok": false, "error": message])
    }

    private var reason: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 422: return "Unprocessable Entity"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }

    func serialized() -> Data {
        let bodyData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(bodyData)
        return out
    }
}
