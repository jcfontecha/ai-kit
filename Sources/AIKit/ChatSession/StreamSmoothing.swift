import Foundation
import AIKitProviders

/// Post-processing throttle for the UI message stream.
///
/// Servers emit text in chunky, irregular bursts (a whole SSE frame lands at
/// once), which makes the assistant message lurch forward in clumps. This funnels
/// those bursts into a steady, word-by-word cadence before the reducer sees them,
/// so the UI updates at an even pace regardless of how the bytes arrive.
///
/// Mirrors the Vercel AI SDK `smoothStream` transform (buffer text/reasoning
/// deltas, release them split on a boundary, delay between releases).
public struct StreamSmoothing: Sendable, Equatable {
  public enum Granularity: Sendable, Equatable {
    /// Release one whitespace-delimited word (with its trailing whitespace) per tick.
    case word
    /// Release one character per tick.
    case character
  }

  /// When `false`, parts pass through untouched at the server's raw cadence.
  public var isEnabled: Bool

  public var granularity: Granularity

  /// Fixed delay between released chunks. The cadence is uniform — a chunk is
  /// released, the funnel waits exactly this long, then releases the next.
  public var delay: Duration

  public init(granularity: Granularity = .word, delay: Duration = .milliseconds(15)) {
    self.isEnabled = true
    self.granularity = granularity
    self.delay = delay
  }

  /// Word-by-word smoothing at a steady cadence.
  public static let `default` = StreamSmoothing()

  /// No smoothing — the UI receives deltas exactly as the server sends them.
  public static let disabled: StreamSmoothing = {
    var smoothing = StreamSmoothing()
    smoothing.isEnabled = false
    return smoothing
  }()
}

extension AsyncThrowingStream where Element == AIUIMessageStreamPart, Failure == Error {
  /// Wraps the stream so text and reasoning deltas are released at a smooth,
  /// even cadence. All other parts (tool calls, finish, data, …) pass through
  /// immediately, after flushing any buffered text to preserve ordering.
  func smoothed(_ config: StreamSmoothing) -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    guard config.isEnabled else { return self }

    let source = self
    return AsyncThrowingStream<AIUIMessageStreamPart, Error> { continuation in
      let task = Task {
        var smoother = StreamSmoother(config: config)
        do {
          for try await part in source {
            try await smoother.ingest(part) { continuation.yield($0) }
          }
          smoother.flush { continuation.yield($0) }
          continuation.finish()
        } catch {
          // Preserve text received so far on a mid-stream disconnect.
          smoother.flush { continuation.yield($0) }
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// The buffering state machine behind ``StreamSmoothing``. Accumulates one
/// `text`/`reasoning` delta stream at a time and drains it on chunk boundaries.
private struct StreamSmoother {
  private enum Kind: Equatable { case text, reasoning }

  let config: StreamSmoothing

  private var kind: Kind?
  private var id: String?
  private var buffer: String = ""
  private var metadata: ProviderMetadata?

  init(config: StreamSmoothing) {
    self.config = config
  }

  mutating func ingest(
    _ part: AIUIMessageStreamPart,
    emit: (AIUIMessageStreamPart) -> Void
  ) async throws {
    switch part {
    case let .textDelta(id, delta, meta):
      try await append(kind: .text, id: id, delta: delta, meta: meta, emit: emit)
    case let .reasoningDelta(id, delta, meta):
      try await append(kind: .reasoning, id: id, delta: delta, meta: meta, emit: emit)
    default:
      // Any non-delta part flushes buffered text first, then passes through
      // unchanged so ordering relative to tool calls / finish is preserved.
      flush(emit: emit)
      emit(part)
    }
  }

  /// Emits any buffered text as a single delta (no delay) and resets state.
  mutating func flush(emit: (AIUIMessageStreamPart) -> Void) {
    if buffer.isEmpty == false {
      emitChunk(buffer, emit: emit)
    }
    kind = nil
    id = nil
    buffer = ""
    metadata = nil
  }

  private mutating func append(
    kind newKind: Kind,
    id newID: String,
    delta: String,
    meta: ProviderMetadata?,
    emit: (AIUIMessageStreamPart) -> Void
  ) async throws {
    if kind != newKind || id != newID {
      flush(emit: emit)
    }
    kind = newKind
    id = newID
    if let meta { metadata = meta }
    buffer += delta
    try await drain(emit: emit)
  }

  private mutating func drain(emit: (AIUIMessageStreamPart) -> Void) async throws {
    while let end = nextChunkEnd(in: buffer) {
      let chunk = String(buffer[buffer.startIndex..<end])
      buffer.removeSubrange(buffer.startIndex..<end)
      emitChunk(chunk, emit: emit)
      try await sleep()
    }
  }

  private func emitChunk(_ text: String, emit: (AIUIMessageStreamPart) -> Void) {
    guard let kind, let id else { return }
    switch kind {
    case .text:
      emit(.textDelta(id: id, delta: text, providerMetadata: metadata))
    case .reasoning:
      emit(.reasoningDelta(id: id, delta: text, providerMetadata: metadata))
    }
  }

  /// Returns the end index (exclusive) of the next releasable chunk, or `nil`
  /// when the buffer does not yet contain a complete one. The chunk spans from
  /// the buffer start through the boundary, so no text is ever dropped.
  private func nextChunkEnd(in buffer: String) -> String.Index? {
    switch config.granularity {
    case .character:
      return buffer.isEmpty ? nil : buffer.index(after: buffer.startIndex)

    case .word:
      // A word is releasable only once its trailing whitespace has arrived, so
      // the final word waits for `flush`. The chunk spans the word plus its
      // trailing whitespace run.
      guard let wordStart = buffer.firstIndex(where: { !$0.isWhitespace }) else { return nil }
      guard var end = buffer[wordStart...].firstIndex(where: { $0.isWhitespace }) else { return nil }
      while end < buffer.endIndex, buffer[end].isWhitespace {
        end = buffer.index(after: end)
      }
      return end
    }
  }

  private func sleep() async throws {
    guard config.delay > .zero else { return }
    try await Task.sleep(for: config.delay)
  }
}
