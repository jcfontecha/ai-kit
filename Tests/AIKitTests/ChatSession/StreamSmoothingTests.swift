import XCTest
@testable import AIKit
import AIKitProviders

final class StreamSmoothingTests: XCTestCase {
  // MARK: Helpers

  private func makeStream(_ parts: [AIUIMessageStreamPart]) -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    AsyncThrowingStream { continuation in
      for part in parts { continuation.yield(part) }
      continuation.finish()
    }
  }

  private func collect(
    _ parts: [AIUIMessageStreamPart],
    _ config: StreamSmoothing
  ) async throws -> [AIUIMessageStreamPart] {
    var output: [AIUIMessageStreamPart] = []
    for try await part in makeStream(parts).smoothed(config) {
      output.append(part)
    }
    return output
  }

  private func text(in parts: [AIUIMessageStreamPart]) -> String {
    parts.reduce(into: "") { result, part in
      if case let .textDelta(_, delta, _) = part { result += delta }
    }
  }

  // MARK: Tests

  func testWordSmoothing_isLossless_andSplitsOnWordBoundaries() async throws {
    // Bursty server frames: whole phrases land at once.
    let input: [AIUIMessageStreamPart] = [
      .textStart(id: "t1"),
      .textDelta(id: "t1", delta: "The quick brown"),
      .textDelta(id: "t1", delta: " fox jumps over the"),
      .textDelta(id: "t1", delta: " lazy dog"),
      .textEnd(id: "t1"),
    ]

    let output = try await collect(input, StreamSmoothing(granularity: .word, delay: .zero))

    // Lossless: smoothed text equals the original concatenation.
    XCTAssertEqual(text(in: output), "The quick brown fox jumps over the lazy dog")

    // Every emitted delta except the final word carries its trailing whitespace,
    // i.e. text is released one word at a time.
    let deltas = output.compactMap { part -> String? in
      if case let .textDelta(_, delta, _) = part { return delta }
      return nil
    }
    XCTAssertGreaterThan(deltas.count, 1, "expected per-word releases, not one blob")
    XCTAssertEqual(deltas.last, "dog", "final word with no trailing space is flushed by textEnd")
    for delta in deltas.dropLast() {
      XCTAssertTrue(delta.last?.isWhitespace == true, "non-final chunk should end on a word boundary: \(delta)")
    }

    // Structural markers pass through and ordering is preserved.
    XCTAssertEqual(output.first, .textStart(id: "t1"))
    XCTAssertEqual(output.last, .textEnd(id: "t1"))
  }

  func testNonDeltaPart_flushesBufferedTextFirst_preservingOrder() async throws {
    let toolCall = AIUIMessageStreamPart.toolInputAvailable(
      .init(toolCallID: "call-1", toolName: "search", input: .object(["q": .string("swift")]))
    )
    let input: [AIUIMessageStreamPart] = [
      .textStart(id: "t1"),
      .textDelta(id: "t1", delta: "Let me look"),  // "look" has no trailing space → buffered
      toolCall,
      .textEnd(id: "t1"),
    ]

    let output = try await collect(input, StreamSmoothing(granularity: .word, delay: .zero))

    XCTAssertEqual(text(in: output), "Let me look")

    // The buffered trailing word must be emitted BEFORE the tool call, not after.
    let toolIndex = try XCTUnwrap(output.firstIndex(of: toolCall))
    let lookIndex = try XCTUnwrap(output.firstIndex { part in
      if case let .textDelta(_, delta, _) = part { return delta.contains("look") }
      return false
    })
    XCTAssertLessThan(lookIndex, toolIndex)
  }

  func testReasoningDeltas_areSmoothedThroughTheSamePath() async throws {
    let input: [AIUIMessageStreamPart] = [
      .reasoningStart(id: "r1"),
      .reasoningDelta(id: "r1", delta: "Thinking about it now"),
      .reasoningEnd(id: "r1"),
    ]

    let output = try await collect(input, StreamSmoothing(granularity: .word, delay: .zero))

    let reasoning = output.reduce(into: "") { result, part in
      if case let .reasoningDelta(_, delta, _) = part { result += delta }
    }
    XCTAssertEqual(reasoning, "Thinking about it now")
    let reasoningDeltas = output.filter { if case .reasoningDelta = $0 { return true } else { return false } }
    XCTAssertGreaterThan(reasoningDeltas.count, 1)
  }

  func testCharacterSmoothing_releasesOneCharacterAtATime() async throws {
    let input: [AIUIMessageStreamPart] = [
      .textStart(id: "t1"),
      .textDelta(id: "t1", delta: "Hey"),
      .textEnd(id: "t1"),
    ]

    let output = try await collect(input, StreamSmoothing(granularity: .character, delay: .zero))

    let deltas = output.compactMap { part -> String? in
      if case let .textDelta(_, delta, _) = part { return delta }
      return nil
    }
    XCTAssertEqual(deltas, ["H", "e", "y"])
  }

  func testDisabled_passesPartsThroughUntouched() async throws {
    let input: [AIUIMessageStreamPart] = [
      .textStart(id: "t1"),
      .textDelta(id: "t1", delta: "The quick brown fox"),
      .textEnd(id: "t1"),
    ]

    let output = try await collect(input, .disabled)

    XCTAssertEqual(output, input)
  }
}
