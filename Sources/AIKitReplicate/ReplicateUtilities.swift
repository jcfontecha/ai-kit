import Foundation

func withoutTrailingSlash(_ value: String) -> String {
  value.hasSuffix("/") ? String(value.dropLast()) : value
}

func combineHeaders(_ headers: [[String: String]?]) -> [String: String] {
  var combined: [String: String] = [:]
  for headerSet in headers {
    guard let headerSet else { continue }
    for (key, value) in headerSet {
      combined[key.lowercased()] = value
    }
  }
  return combined
}

func withUserAgentSuffix(_ headers: [String: String], suffixParts: [String]) -> [String: String] {
  var updated = headers
  let current = headers["user-agent"] ?? headers["User-Agent"] ?? ""
  let suffix = ([current] + suffixParts).filter { $0.isEmpty == false }.joined(separator: " ")
  updated["user-agent"] = suffix
  return updated
}

