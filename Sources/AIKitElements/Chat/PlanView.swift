import SwiftUI
import AIKit

/// A collapsible checklist of plan items decoded from a ``ChatDataPart`` with
/// `type == "data-plan"`. Items show `checkmark.circle` / `circle.dotted` / `circle`
/// for done / in-progress / pending.
///
/// Expected `data` shape (array, or object with an `items` key):
/// `[{ "title": String, "status": "pending" | "inProgress" | "done" }]`.
///
/// Built on ``ChatSecondaryDisclosureGroup``.
///
/// Wire it through ``AssistantMessage`` via the data-renderer hook:
/// ```swift
/// AssistantMessage(parts: parts)
///   .assistantMessageDataRenderer { part in
///     PlanView(part: part)
///   }
/// ```
public struct PlanView: View {
  public struct Item: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var status: ChatStepStatus

    public init(id: String = UUID().uuidString, title: String, status: ChatStepStatus = .pending) {
      self.id = id
      self.title = title
      self.status = status
    }
  }

  public static let dataType = "data-plan"

  public var items: [Item]

  public init(items: [Item]) {
    self.items = items
  }

  /// Builds the view if `part.type == "data-plan"`, otherwise returns `nil`
  /// so the data-renderer hook can fall through to other renderers.
  public init?(part: ChatDataPart) {
    guard part.type == Self.dataType else { return nil }
    self.items = Self.decodeItems(part.data)
  }

  static func decodeItems(_ data: JSONValue) -> [Item] {
    data.items("items").enumerated().map { index, item in
      Item(
        id: item["id"]?.stringValue ?? "item-\(index)",
        title: item["title"]?.stringValue ?? "",
        status: ChatStepStatus(jsonValue: item["status"])
      )
    }
  }

  private var doneCount: Int {
    items.filter { $0.status == .done }.count
  }

  public var body: some View {
    ChatSecondaryDisclosureGroup {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(items) { item in
          ChatLeadingIconLabel {
            ChatStepStatusIcon(status: item.status)
          } title: {
            Text(item.title)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
    } label: {
      Text("Plan (\(doneCount)/\(items.count))")
    }
  }
}
