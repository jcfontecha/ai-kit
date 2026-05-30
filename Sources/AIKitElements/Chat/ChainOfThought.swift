import SwiftUI
import AIKit

/// An ordered, collapsible list of reasoning steps decoded from a ``ChatDataPart``
/// with `type == "data-chain-of-thought"`.
///
/// Expected `data` shape (array, or object with a `steps` key):
/// `[{ "label": String, "status": "pending" | "inProgress" | "done" }]`.
///
/// Built on ``ChatSecondaryDisclosureGroup`` + ``ChatLeadingIconLabel``.
///
/// Wire it through ``AssistantMessage`` via the data-renderer hook:
/// ```swift
/// AssistantMessage(parts: parts)
///   .assistantMessageDataRenderer { part in
///     ChainOfThought(part: part)
///   }
/// ```
public struct ChainOfThought: View {
  public struct Step: Identifiable, Equatable {
    public var id: String
    public var label: String
    public var status: ChatStepStatus

    public init(id: String = UUID().uuidString, label: String, status: ChatStepStatus = .done) {
      self.id = id
      self.label = label
      self.status = status
    }
  }

  public static let dataType = "data-chain-of-thought"

  public var steps: [Step]

  public init(steps: [Step]) {
    self.steps = steps
  }

  /// Builds the view if `part.type == "data-chain-of-thought"`, otherwise returns `nil`
  /// so the data-renderer hook can fall through to other renderers.
  public init?(part: ChatDataPart) {
    guard part.type == Self.dataType else { return nil }
    self.steps = Self.decodeSteps(part.data)
  }

  static func decodeSteps(_ data: JSONValue) -> [Step] {
    data.items("steps").enumerated().map { index, item in
      Step(
        id: item["id"]?.stringValue ?? "step-\(index)",
        label: item["label"]?.stringValue ?? "",
        status: ChatStepStatus(jsonValue: item["status"])
      )
    }
  }

  public var body: some View {
    ChatSecondaryDisclosureGroup {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(steps) { step in
          ChatLeadingIconLabel {
            ChatStepStatusIcon(status: step.status)
          } title: {
            Text(step.label)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
    } label: {
      Text("Chain of thought")
    }
  }
}
