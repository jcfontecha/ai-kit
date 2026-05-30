import Foundation
import AIKitProviders

/// JSON-RPC 2.0 framing helpers, expressed over `JSONValue` (which is `Codable`), plus the SSE
/// decoding needed for MCP's Streamable HTTP transport where a single POST may answer with either
/// `application/json` or `text/event-stream`.
enum JSONRPC {
  /// Builds a JSON-RPC request object. `id` is omitted for notifications.
  static func message(id: Int?, method: String, params: JSONValue?) -> JSONValue {
    var fields: [String: JSONValue] = [
      "jsonrpc": .string("2.0"),
      "method": .string(method),
    ]
    if let id { fields["id"] = .number(Double(id)) }
    if let params { fields["params"] = params }
    return .object(fields)
  }

  static func encode(_ value: JSONValue) throws -> Data {
    try JSONEncoder().encode(value)
  }

  static func decode(_ data: Data) -> JSONValue? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else { return nil }
    return JSONValue.from(object)
  }

  static func decode(_ string: String) -> JSONValue? {
    guard let data = string.data(using: .utf8) else { return nil }
    return decode(data)
  }

  /// Extracts the `data:` payloads from an SSE response body. The MCP request/response pattern keeps
  /// the stream open only until the matching response is delivered, so buffering the full body is
  /// sufficient.
  static func sseEvents(from data: Data) -> [String] {
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    var payloads: [String] = []
    for block in text.components(separatedBy: "\n\n") {
      var dataLines: [String] = []
      for line in block.split(separator: "\n", omittingEmptySubsequences: true) {
        guard line.hasPrefix("data:") else { continue }
        let payload = line.dropFirst(5)
        dataLines.append(String(payload.first == " " ? payload.dropFirst() : Substring(payload)))
      }
      if dataLines.isEmpty == false {
        payloads.append(dataLines.joined(separator: "\n"))
      }
    }
    return payloads
  }

  /// Returns true when a JSON-RPC `id` field equals the integer id we sent.
  static func idMatches(_ value: JSONValue?, _ id: Int) -> Bool {
    switch value {
    case let .number(n): return Int(n) == id
    case let .string(s): return s == String(id)
    default: return false
    }
  }
}
