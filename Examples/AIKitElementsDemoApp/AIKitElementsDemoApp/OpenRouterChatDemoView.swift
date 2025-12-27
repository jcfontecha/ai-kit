import SwiftUI
import Combine

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
        messages: DemoContent.initialMessages,
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
        messages.isEmpty ? DemoContent.initialMessages : messages
      }
      let stream = await session.updates()
      for await snap in stream {
        if Task.isCancelled { return }
        await MainActor.run { self.snapshot = snap }
      }
    }

    snapshot = .init(status: .ready, messages: DemoContent.initialMessages, errorDescription: nil)
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
}

#Preview {
  OpenRouterChatDemoView()
}
