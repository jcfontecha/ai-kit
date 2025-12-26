import Foundation

public struct TestClock: Sendable {
  public var now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date) {
    self.now = now
  }

  public static func fixed(_ date: Date) -> TestClock {
    .init(now: { date })
  }
}

