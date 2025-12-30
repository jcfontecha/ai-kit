import Foundation

public typealias StopCondition = @Sendable (_ steps: [StepResult]) async -> Bool

public enum Stop {
  public static func stepCountIs(_ n: Int) -> StopCondition {
    { steps in steps.count == n }
  }

  public static func never() -> StopCondition {
    { _ in false }
  }
}
