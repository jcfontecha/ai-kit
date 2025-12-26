import Foundation

public enum AsyncTestHelpers {
  public static func collect<S: AsyncSequence>(
    _ sequence: S,
    limit: Int? = nil
  ) async rethrows -> [S.Element] {
    var result: [S.Element] = []
    var remaining = limit

    for try await element in sequence {
      result.append(element)
      if let r = remaining {
        let n = r - 1
        remaining = n
        if n <= 0 { break }
      }
    }

    return result
  }
}

