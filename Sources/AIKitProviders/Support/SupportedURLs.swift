import Foundation

public struct URLPattern: Sendable, Equatable {
  public let pattern: String
  public let options: NSRegularExpression.Options

  public init(_ pattern: String, options: NSRegularExpression.Options = []) {
    self.pattern = pattern
    self.options = options
  }

  public func matches(_ url: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return false
    }
    let range = NSRange(url.startIndex..<url.endIndex, in: url)
    return regex.firstMatch(in: url, range: range) != nil
  }
}

public typealias SupportedURLPatterns = [String: [URLPattern]]

public func isURLSupported(
  mediaType: String,
  url: String,
  supportedURLs: SupportedURLPatterns
) -> Bool {
  let urlLower = url.lowercased()
  let mediaTypeLower = mediaType.lowercased()

  return supportedURLs
    .map { key, regexes in
      let keyLower = key.lowercased()
      if keyLower == "*" || keyLower == "*/*" {
        return (mediaTypePrefix: "", regexes: regexes)
      }
      return (mediaTypePrefix: keyLower.replacingOccurrences(of: "*", with: ""), regexes: regexes)
    }
    .filter { mediaTypeLower.hasPrefix($0.mediaTypePrefix) }
    .flatMap { $0.regexes }
    .contains { $0.matches(urlLower) }
}
