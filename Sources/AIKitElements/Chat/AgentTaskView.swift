import SwiftUI

/// A collapsible "task": a title with a list of sub-steps.
/// Built on ``ChatSecondaryDisclosureGroup`` + ``ChatLeadingIconLabel``.
///
/// Named `AgentTaskView` (not `Task`) to avoid colliding with `Swift.Task`.
public struct AgentTaskView: View {
  /// A single sub-step. `status` defaults to `.done`.
  public struct Step: Identifiable, Equatable {
    public var id: String
    public var text: String
    public var status: ChatStepStatus

    public init(id: String = UUID().uuidString, text: String, status: ChatStepStatus = .done) {
      self.id = id
      self.text = text
      self.status = status
    }
  }

  public var title: String
  public var steps: [Step]

  public init(title: String, steps: [Step]) {
    self.title = title
    self.steps = steps
  }

  public init(title: String, steps: [String]) {
    self.title = title
    self.steps = steps.map { Step(text: $0) }
  }

  public var body: some View {
    ChatSecondaryDisclosureGroup {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(steps) { step in
          ChatLeadingIconLabel {
            ChatStepStatusIcon(status: step.status)
          } title: {
            Text(step.text)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
    } label: {
      Text(title)
    }
  }
}
