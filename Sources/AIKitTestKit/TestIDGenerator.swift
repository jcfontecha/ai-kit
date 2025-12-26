import Foundation

public struct TestIDGenerator: Sendable {
  private let lock = NSLock()
  private var next: Int
  public var prefix: String

  public init(prefix: String = "id", startAt: Int = 0) {
    self.prefix = prefix
    self.next = startAt
  }

  public mutating func generate() -> String {
    lock.lock()
    defer { lock.unlock() }
    let value = "\(prefix)-\(next)"
    next += 1
    return value
  }
}

