import XCTest
import SwiftUI

import AIKit
@testable import AIKitElements

@MainActor
final class AIKitElementsUnitTests: XCTestCase {

  // MARK: - ChatStepStatus (JSONValue -> status + icon)

  func testChatStepStatus_decodesKnownRawValues() {
    XCTAssertEqual(ChatStepStatus(jsonValue: .string("pending")), .pending)
    XCTAssertEqual(ChatStepStatus(jsonValue: .string("inProgress")), .inProgress)
    XCTAssertEqual(ChatStepStatus(jsonValue: .string("done")), .done)
  }

  func testChatStepStatus_defaultsToPendingForUnknownOrAbsentOrWrongType() {
    XCTAssertEqual(ChatStepStatus(jsonValue: .string("bogus")), .pending)
    XCTAssertEqual(ChatStepStatus(jsonValue: nil), .pending)
    XCTAssertEqual(ChatStepStatus(jsonValue: .number(3)), .pending)
    XCTAssertEqual(ChatStepStatus(jsonValue: .bool(true)), .pending)
    XCTAssertEqual(ChatStepStatus(jsonValue: .null), .pending)
  }

  func testChatStepStatus_symbolNameSelection() {
    XCTAssertEqual(ChatStepStatus.pending.symbolName, "circle")
    XCTAssertEqual(ChatStepStatus.inProgress.symbolName, "circle.dotted")
    XCTAssertEqual(ChatStepStatus.done.symbolName, "checkmark.circle")
  }

  // MARK: - JSONValue.items helper (array OR object-wrapping-key)

  func testJSONValueItems_returnsArrayDirectly() {
    let value = JSONValue.array([.string("a"), .string("b")])
    XCTAssertEqual(value.items("steps").count, 2)
  }

  func testJSONValueItems_unwrapsObjectKey() {
    let value = JSONValue.object(["steps": .array([.string("a")])])
    XCTAssertEqual(value.items("steps").count, 1)
  }

  func testJSONValueItems_returnsEmptyForMissingKeyOrWrongType() {
    XCTAssertTrue(JSONValue.object([:]).items("steps").isEmpty)
    XCTAssertTrue(JSONValue.string("nope").items("steps").isEmpty)
    XCTAssertTrue(JSONValue.object(["steps": .string("not an array")]).items("steps").isEmpty)
  }

  // MARK: - ChainOfThought decoder + failable init

  func testChainOfThought_initFromMatchingPart_decodesSteps() {
    let part = ChatDataPart(
      type: "data-chain-of-thought",
      data: .array([
        .object(["id": .string("s1"), "label": .string("Look up weather"), "status": .string("done")]),
        .object(["label": .string("Summarize"), "status": .string("inProgress")]),
        .object(["label": .string("Wait")]),
      ])
    )

    let view = ChainOfThought(part: part)
    XCTAssertNotNil(view)
    let steps = view!.steps
    XCTAssertEqual(steps.count, 3)

    XCTAssertEqual(steps[0].id, "s1")
    XCTAssertEqual(steps[0].label, "Look up weather")
    XCTAssertEqual(steps[0].status, .done)

    // Missing id falls back to "step-<index>".
    XCTAssertEqual(steps[1].id, "step-1")
    XCTAssertEqual(steps[1].label, "Summarize")
    XCTAssertEqual(steps[1].status, .inProgress)

    // Missing status defaults to .pending; missing label -> "".
    XCTAssertEqual(steps[2].status, .pending)
    XCTAssertEqual(steps[2].label, "Wait")
  }

  func testChainOfThought_initFromObjectWithStepsKey() {
    let part = ChatDataPart(
      type: "data-chain-of-thought",
      data: .object([
        "steps": .array([
          .object(["label": .string("Only step"), "status": .string("done")])
        ])
      ])
    )
    let view = ChainOfThought(part: part)
    XCTAssertEqual(view?.steps.count, 1)
    XCTAssertEqual(view?.steps.first?.status, .done)
  }

  func testChainOfThought_initReturnsNilForWrongType() {
    let part = ChatDataPart(type: "data-plan", data: .array([]))
    XCTAssertNil(ChainOfThought(part: part))
  }

  func testChainOfThought_handlesEmptyAndMalformedDataGracefully() {
    // Empty array.
    XCTAssertEqual(ChainOfThought(part: .init(type: "data-chain-of-thought", data: .array([])))?.steps.count, 0)
    // Wrong shape entirely (string instead of array/object).
    XCTAssertEqual(ChainOfThought(part: .init(type: "data-chain-of-thought", data: .string("oops")))?.steps.count, 0)
    // null payload.
    XCTAssertEqual(ChainOfThought(part: .init(type: "data-chain-of-thought", data: .null))?.steps.count, 0)
    // Item that isn't an object -> label "" and status pending, no crash.
    let mixed = ChainOfThought(part: .init(
      type: "data-chain-of-thought",
      data: .array([.string("not-an-object"), .number(7)])
    ))
    XCTAssertEqual(mixed?.steps.count, 2)
    XCTAssertEqual(mixed?.steps.allSatisfy { $0.label == "" && $0.status == .pending }, true)
  }

  // MARK: - PlanView decoder + failable init

  func testPlanView_initFromMatchingPart_decodesItems() {
    let part = ChatDataPart(
      type: "data-plan",
      data: .array([
        .object(["id": .string("p1"), "title": .string("Draft"), "status": .string("done")]),
        .object(["title": .string("Review"), "status": .string("inProgress")]),
        .object(["title": .string("Ship")]),
      ])
    )

    let view = PlanView(part: part)
    XCTAssertNotNil(view)
    let items = view!.items
    XCTAssertEqual(items.count, 3)

    XCTAssertEqual(items[0].id, "p1")
    XCTAssertEqual(items[0].title, "Draft")
    XCTAssertEqual(items[0].status, .done)

    XCTAssertEqual(items[1].id, "item-1")
    XCTAssertEqual(items[1].status, .inProgress)

    // Missing status defaults to .pending.
    XCTAssertEqual(items[2].status, .pending)
    XCTAssertEqual(items[2].title, "Ship")
  }

  func testPlanView_initFromObjectWithItemsKey() {
    let part = ChatDataPart(
      type: "data-plan",
      data: .object([
        "items": .array([
          .object(["title": .string("One"), "status": .string("done")]),
          .object(["title": .string("Two"), "status": .string("pending")]),
        ])
      ])
    )
    let view = PlanView(part: part)
    XCTAssertEqual(view?.items.count, 2)
  }

  func testPlanView_initReturnsNilForWrongType() {
    let part = ChatDataPart(type: "data-chain-of-thought", data: .array([]))
    XCTAssertNil(PlanView(part: part))
  }

  func testPlanView_handlesEmptyAndMalformedDataGracefully() {
    XCTAssertEqual(PlanView(part: .init(type: "data-plan", data: .array([])))?.items.count, 0)
    XCTAssertEqual(PlanView(part: .init(type: "data-plan", data: .string("oops")))?.items.count, 0)
    XCTAssertEqual(PlanView(part: .init(type: "data-plan", data: .null))?.items.count, 0)
  }

  // MARK: - ContextUsage number formatting + fraction

  func testContextUsage_formatsThousandsAndUnitsLikeVercel() {
    XCTAssertEqual(ContextUsage.format(0), "0")
    XCTAssertEqual(ContextUsage.format(999), "999")
    XCTAssertEqual(ContextUsage.format(1000), "1k")
    XCTAssertEqual(ContextUsage.format(12_000), "12k")
    XCTAssertEqual(ContextUsage.format(128_000), "128k")
    // Fractional thousands keep one decimal.
    XCTAssertEqual(ContextUsage.format(12_500), "12.5k")
    // Rounds to one decimal place.
    XCTAssertEqual(ContextUsage.format(12_340), "12.3k")
  }

  func testContextUsage_fractionClampsAndGuardsZeroMax() {
    XCTAssertEqual(ContextUsage(used: 64, max: 128).fractionValue, 0.5, accuracy: 0.0001)
    XCTAssertEqual(ContextUsage(used: 0, max: 128).fractionValue, 0, accuracy: 0.0001)
    // Over capacity clamps to 1.
    XCTAssertEqual(ContextUsage(used: 256, max: 128).fractionValue, 1, accuracy: 0.0001)
    // Negative clamps to 0.
    XCTAssertEqual(ContextUsage(used: -10, max: 128).fractionValue, 0, accuracy: 0.0001)
    // Zero max guards against divide-by-zero.
    XCTAssertEqual(ContextUsage(used: 10, max: 0).fractionValue, 0, accuracy: 0.0001)
  }

  // MARK: - Suggestion / ModelSelector callbacks

  func testSuggestion_onSelectFiresWithItsText() {
    var received: String?
    let suggestion = Suggestion("Make a plan") { received = $0 }
    suggestion.onSelect(suggestion.text)
    XCTAssertEqual(received, "Make a plan")
  }

  func testModelSelector_currentNameResolvesFromSelection() {
    let options = [
      ModelOption(id: "gpt", name: "GPT-5"),
      ModelOption(id: "claude", name: "Claude"),
    ]
    var selection = "claude"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let selector = ModelSelector(options: options, selection: binding)
    XCTAssertEqual(selector.currentNameValue, "Claude")
  }

  func testModelSelector_currentNameFallsBackToRawSelectionWhenUnknown() {
    let options = [ModelOption(id: "gpt", name: "GPT-5")]
    var selection = "mystery-model"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let selector = ModelSelector(options: options, selection: binding)
    XCTAssertEqual(selector.currentNameValue, "mystery-model")
  }

  // MARK: - assistantMessageDataRenderer hook

  /// A registered renderer is invoked for a `.data` part, receiving the decoded
  /// `ChatDataPart`.
  func testAssistantMessageDataRenderer_isInvokedForDataPart() {
    let recorder = PartRecorder()

    let parts: [ChatMessagePart] = [
      .data(.init(type: "data-plan", id: "d-1", data: .object(["items": .array([])])))
    ]

    let view = AssistantMessage(messageID: "m-1", parts: parts)
      .assistantMessageDataRenderer { part -> AnyView in
        recorder.received.append(part)
        return AnyView(Text("rendered"))
      }

    forceRender(view)

    // SwiftUI may evaluate the body more than once; assert it fired and always
    // received the same decoded part.
    XCTAssertFalse(recorder.received.isEmpty)
    XCTAssertTrue(recorder.received.allSatisfy { $0.type == "data-plan" && $0.id == "d-1" })
  }

  /// With no renderer registered, a `.data` part renders nothing and does not
  /// crash — preserving prior behavior.
  func testAssistantMessageDataRenderer_defaultRendersNothing() {
    let parts: [ChatMessagePart] = [
      .data(.init(type: "data-plan", id: "d-1", data: .object([:])))
    ]
    // No renderer registered: must render without invoking any closure / crashing.
    forceRender(AssistantMessage(messageID: "m-1", parts: parts))
  }

  /// Forces a SwiftUI `body` evaluation so environment-driven closures fire.
  private func forceRender<V: View>(_ view: V) {
    let renderer = ImageRenderer(content: view.frame(width: 320, height: 200))
    _ = renderer.cgImage
  }
}

/// Reference-type recorder so a `@Sendable`/escaping renderer closure can append
/// the parts it received.
private final class PartRecorder: @unchecked Sendable {
  var received: [ChatDataPart] = []
}
