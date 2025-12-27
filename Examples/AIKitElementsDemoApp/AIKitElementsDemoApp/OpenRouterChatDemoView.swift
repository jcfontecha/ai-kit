import SwiftUI
import Combine
import MarkdownUI

import AIKitCore
import AIKitOpenRouter
import AIKitProviders
import AIKitElements

struct OpenRouterChatDemoView: View {
  @AppStorage(AppSettings.openRouterAPIKeyKey) private var apiKey: String = ""
  @AppStorage(AppSettings.openRouterModelIDKey) private var modelID: String = AppSettings.defaultOpenRouterModelID

  @StateObject private var store = OpenRouterChatStore()
  @State private var text: String = ""

  var body: some View {
    Conversation(messages: store.snapshot.messages, bottomOverlayHeight: composerHeight) { message in
      DemoChatMessageView(message: message)
        .id(message.id)
    }
    .overlay(alignment: .top) {
      if let error = store.snapshot.errorDescription {
        Text(error)
          .font(.caption)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(Color.red.opacity(0.85))
      }
    }
    .overlay(alignment: .topTrailing) {
      HStack(spacing: 8) {
        Button("Clear") {
          Task { await store.clear() }
        }
        .buttonStyle(.bordered)

        if store.snapshot.status == .streaming || store.snapshot.status == .submitted {
          Button("Stop") { Task { await store.stop() } }
            .buttonStyle(.borderedProminent)
        }
      }
      .padding(10)
    }
    .task {
      store.configureIfPossible(apiKey: apiKey, modelID: modelID)
    }
    .onChange(of: apiKey) { _, _ in
      store.configureIfPossible(apiKey: apiKey, modelID: modelID)
    }
    .onChange(of: modelID) { _, _ in
      store.configureIfPossible(apiKey: apiKey, modelID: modelID)
    }
    .promptInputBottomBar(
      text: $text,
      status: store.snapshot.status,
      height: $composerHeight,
      onSend: { message in
        Task { await store.send(text: message) }
      },
      onStop: {
        Task { await store.stop() }
      }
    )
  }

  @State private var composerHeight: CGFloat = 0
}

@MainActor
final class OpenRouterChatStore: ObservableObject {
  @Published var snapshot: ChatSessionSnapshot = .init(status: .ready, messages: [], errorDescription: nil)

  private var session: ChatSession?
  private var updatesTask: Task<Void, Never>?
  private var configuredKey: String = ""
  private var configuredModelID: String = ""

  func configureIfPossible(apiKey: String, modelID: String) {
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)

    if apiKey.isEmpty || modelID.isEmpty {
      updatesTask?.cancel()
      updatesTask = nil
      session = nil
      configuredKey = ""
      configuredModelID = ""
      snapshot = .init(
        status: .ready,
        messages: Self.demoMessages,
        errorDescription: apiKey.isEmpty ? "Set an OpenRouter API key in Settings to use this demo." : "Set a model ID in Settings."
      )
      return
    }

    guard apiKey != configuredKey || modelID != configuredModelID || session == nil else {
      return
    }

    configuredKey = apiKey
    configuredModelID = modelID

    updatesTask?.cancel()
    updatesTask = nil

    let provider = createOpenRouter(.init(apiKey: apiKey))
    let model = provider.chat(modelID)
    let agent = ToolLoopAgent<Void, Output.Text>(model: model, output: .init())

    let session = ChatSession(.init(agent: agent))
    self.session = session

    updatesTask = Task { [weak self] in
      guard let self else { return }
      await session.setMessages { messages in
        messages.isEmpty ? Self.demoMessages : messages
      }
      let stream = await session.updates()
      for await snap in stream {
        if Task.isCancelled { return }
        await MainActor.run { self.snapshot = snap }
      }
    }

    snapshot = .init(status: .ready, messages: Self.demoMessages, errorDescription: nil)
  }

  func send(text: String) async {
    guard let session else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }

    let draft = ChatDraftMessage(
      role: .user,
      parts: [
        .text(.init(id: UUID().uuidString, text: trimmed, state: .done)),
      ]
    )
    await session.send(draft)
  }

  func stop() async {
    await session?.stop()
  }

  func clear() async {
    guard let session else { return }
    await session.setMessages { _ in [] }
  }

  nonisolated private static var demoMessages: [ChatMessage] {
    [
      ChatMessage(
        id: "demo.assistant.animal-crossing.1",
        role: .assistant,
        parts: [
          .text(.init(id: "demo.assistant.animal-crossing.1.text", text: animalCrossingP1, state: .done)),
        ]
      ),
      ChatMessage(
        id: "demo.assistant.animal-crossing.2",
        role: .assistant,
        parts: [
          .text(.init(id: "demo.assistant.animal-crossing.2.text", text: animalCrossingP2, state: .done)),
        ]
      ),
      ChatMessage(
        id: "demo.assistant.animal-crossing.3",
        role: .assistant,
        parts: [
          .text(.init(id: "demo.assistant.animal-crossing.3.text", text: animalCrossingP3, state: .done)),
        ]
      ),
    ]
  }

  nonisolated private static let animalCrossingP1: String = """
  Animal Crossing is at its best when you treat it like a tiny daily ritual instead of a game you “finish.” You check in, water a few flowers, talk to your neighbors, and do a lap around the island to see what changed overnight. The pace is intentionally gentle, and the fun comes from noticing small details—seasonal lighting, shop stock, a surprise visit from a villager, or a new message in the mailbox—rather than chasing a single objective. It’s the kind of game that rewards slowing down.
  """

  nonisolated private static let animalCrossingP2: String = """
  The island design loop is where it becomes personal. You start with rough paths and simple furniture, then gradually refine everything: terraform a hill to frame a view, move a house to open up a plaza, or build a cozy market street near Nook’s Cranny. It’s less about a “perfect” layout and more about creating spaces that feel lived-in—reading nooks, picnic spots, a cluttered workshop, a café corner—so walking around your island feels intentional.
  """

  nonisolated private static let animalCrossingP3: String = """
  And then there’s the social layer: neighbors who develop tiny running jokes, trading turnip prices, sending letters, and visiting friends’ islands for inspiration. Even when you’re playing solo, it still feels communal—like you’re part of a quiet town where everyone has their own routines. That gentle sense of connection is a big part of why the series feels comforting when you just want to unwind.
  """
}

private struct DemoChatMessageView: View {
  let message: ChatMessage

  var body: some View {
    switch message.role {
    case .user:
      HStack {
        Spacer(minLength: 24)
        userBubble(text: messageText)
      }

    case .assistant:
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
          switch part {
          case .text(let text):
            Markdown(text.text)
              .frame(maxWidth: .infinity, alignment: .leading)
          case .reasoning(let reasoning):
            DisclosureGroup("Reasoning") {
              Markdown(reasoning.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
          default:
            EmptyView()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case .system:
      Text(messageText)
        .font(.caption)
        .foregroundStyle(.secondary)

    case .tool:
      Text("Tool role message (unsupported in demo)")
        .font(.caption)
        .foregroundStyle(.secondary)

    @unknown default:
      Text("Unsupported message role: \(message.role.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var messageText: String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private func userBubble(text: String) -> some View {
    Text(text)
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.secondary.opacity(0.12))
      }
  }
}

#Preview {
  OpenRouterChatDemoView()
}
