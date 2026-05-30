import SwiftUI
import AIKit
import AIKitElements

/// Shows the streaming "funnel" in action: the same chunky server response is
/// played into two chat stores at once — one raw, one smoothed — so the
/// difference in cadence is visible side by side. Granularity and speed are
/// configurable so the effect is easy to see. No API key required.
struct StreamSmoothingDemoView: View {
  enum Granularity: String, CaseIterable, Identifiable {
    case word = "Word"
    case character = "Character"
    var id: String { rawValue }

    var smoothing: StreamSmoothing.Granularity {
      switch self {
      case .word: .word
      case .character: .character
      }
    }
  }

  @State private var granularity: Granularity = .character
  @State private var delayMS: Double = 16
  @State private var runID = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("The same bursty server response, played into both panes at once. The left renders deltas exactly as they arrive; the right funnels them into a steady cadence. Tweak the controls, then Replay.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Picker("Release", selection: $granularity) {
        ForEach(Granularity.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text("Speed")
          Spacer()
          Text("\(Int(delayMS)) ms / \(granularity == .character ? "char" : "word")")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .font(.caption)
        HStack(spacing: 8) {
          Text("Slow").font(.caption2).foregroundStyle(.secondary)
          // Inverted so dragging right = faster (smaller delay).
          Slider(value: $delayMS, in: 4...80)
            .environment(\.layoutDirection, .rightToLeft)
          Text("Fast").font(.caption2).foregroundStyle(.secondary)
        }
      }

      Button {
        runID += 1
      } label: {
        Label("Replay", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderedProminent)

      // `.id` recreates the comparison (and its fresh stores) whenever the
      // settings change or Replay is tapped, so the new config takes effect.
      SmoothingComparison(
        smoothing: StreamSmoothing(granularity: granularity.smoothing, delay: .milliseconds(Int(delayMS)))
      )
      .id("\(runID)-\(granularity.rawValue)-\(Int(delayMS))")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct SmoothingComparison: View {
  @StateObject private var rawStore: ChatStore
  @StateObject private var smoothStore: ChatStore

  init(smoothing: StreamSmoothing) {
    let transport = BurstyChatTransport()
    _rawStore = StateObject(wrappedValue: ChatStore(transport: transport, smoothing: .disabled))
    _smoothStore = StateObject(wrappedValue: ChatStore(transport: transport, smoothing: smoothing))
  }

  var body: some View {
    VStack(spacing: 12) {
      pane("Raw stream", store: rawStore, tint: .secondary)
      pane("Smoothed", store: smoothStore, tint: .blue)
    }
    .task {
      // Fire the same prompt into both stores simultaneously.
      rawStore.sendMessage(Self.prompt)
      smoothStore.sendMessage(Self.prompt)
    }
  }

  private func pane(_ title: String, store: ChatStore, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(tint)
        if store.isLoading {
          ProgressView().controlSize(.mini)
        }
      }
      Conversation(messages: store.messages, status: store.status)
        .frame(height: 230)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private static let prompt = "What is smooth streaming?"
}

/// A fake transport that replays a canned answer in large, sentence-sized bursts
/// spaced by a real delay — the way a server's SSE frames actually arrive. Big
/// bursts make the raw pane visibly lurch; the smoothed pane spreads each burst
/// out into a continuous flow.
private struct BurstyChatTransport: ChatTransport {
  /// Big, paragraph-sized chunks. Each lands as a single delta, so the raw pane
  /// finishes in a few large jumps almost immediately.
  private let bursts: [String] = [
    "Smooth streaming is a post-processing throttle. Instead of repainting the screen every time a network chunk lands, ",
    "it buffers the incoming text and releases it at a steady pace. The server can stream in big, uneven bursts — ",
    "but the reader always sees a calm, continuous flow of words.",
  ]

  /// Gap between bursts. Short, so the raw pane is done in a few hundred ms while
  /// the smoothed pane is still gliding through the buffered text.
  private let burstDelay: Duration = .milliseconds(120)

  func sendMessages(
    _ options: ChatTransportSendMessagesOptions
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
    let bursts = bursts
    let burstDelay = burstDelay
    return AsyncThrowingStream { continuation in
      let task = Task {
        let id = "text-1"
        continuation.yield(.start())
        continuation.yield(.startStep)
        continuation.yield(.textStart(id: id))
        do {
          for burst in bursts {
            try await Task.sleep(for: burstDelay)
            continuation.yield(.textDelta(id: id, delta: burst))
          }
          continuation.yield(.textEnd(id: id))
          continuation.yield(.finishStep)
          continuation.yield(.finish())
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func reconnectToStream(
    _ options: ChatTransportReconnectToStreamOptions
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>? {
    nil
  }
}

#Preview {
  StreamSmoothingDemoView()
}
