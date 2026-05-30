import SwiftUI

/// Shared three-state status for ordered/checklist steps
/// (``AgentTaskView``, ``ChainOfThought``, ``PlanView``).
public enum ChatStepStatus: String, Sendable, Equatable {
  case pending
  case inProgress
  case done

  var symbolName: String {
    switch self {
    case .pending: "circle"
    case .inProgress: "circle.dotted"
    case .done: "checkmark.circle"
    }
  }
}

/// The leading status glyph used by step rows. Monochromatic, secondary tint.
struct ChatStepStatusIcon: View {
  var status: ChatStepStatus

  var body: some View {
    Image(systemName: status.symbolName)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}
