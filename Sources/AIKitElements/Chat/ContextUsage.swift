import SwiftUI

/// A compact context-window usage indicator, e.g. "12k / 128k" with a thin
/// progress bar. Presentational only.
public struct ContextUsage: View {
  public var used: Int
  public var max: Int

  public init(used: Int, max: Int) {
    self.used = used
    self.max = max
  }

  public var body: some View {
    HStack(spacing: 8) {
      Text("\(format(used)) / \(format(max))")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()

      Capsule()
        .fill(Color.secondary.opacity(0.12))
        .frame(width: 56, height: 2)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(Color.secondary)
            .frame(width: 56 * fraction, height: 2)
        }
    }
  }

  private var fraction: CGFloat {
    guard max > 0 else { return 0 }
    return min(1, Swift.max(0, CGFloat(used) / CGFloat(max)))
  }

  private func format(_ value: Int) -> String {
    if value >= 1000 {
      let thousands = Double(value) / 1000
      let rounded = (thousands * 10).rounded() / 10
      let trimmed = rounded.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(rounded))
        : String(rounded)
      return "\(trimmed)k"
    }
    return String(value)
  }
}
