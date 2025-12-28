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
  @State private var composerHeight: CGFloat = 0

  var body: some View {
    ZStack {
      Conversation(messages: store.snapshot.messages, bottomOverlayHeight: composerHeight) { message in
        DemoMessageRow(message: message)
      }
      .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
        Task { await store.respondToToolApproval(approvalID: approvalID, approved: approved, reason: reason) }
      }

      if store.snapshot.messages.isEmpty {
        Text("Start a conversation")
          .font(.headline)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    .task {
      store.configureIfPossible(apiKey: apiKey, modelID: modelID)
    }
    .onChange(of: apiKey) { _, _ in
      store.configureIfPossible(apiKey: apiKey, modelID: modelID)
    }
    .onChange(of: modelID) { _, _ in
      store.configureIfPossible(apiKey: apiKey, modelID: modelID)
    }
  }
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

  func respondToToolApproval(approvalID: String, approved: Bool, reason: String?) async {
    await session?.addToolApprovalResponse(approvalID: approvalID, approved: approved, reason: reason)
  }

  func clear() async {
    guard let session else { return }
    await session.setMessages { _ in [] }
  }
}

private struct DemoMessageRow: View {
  let message: ChatMessage

  var body: some View {
    switch message.role {
    case .user:
      HStack(alignment: .top) {
        Spacer(minLength: 24)
        UserMessage(parts: message.parts)
      }

    case .assistant:
      HStack(alignment: .top) {
        AssistantMessage(parts: message.parts) { text in
          Markdown(text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Spacer(minLength: 24)
      }

    case .system:
      Text(messageText(parts: message.parts))
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .tool:
      Text("Tool role message")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

    @unknown default:
      Text("Unsupported role: \(message.role.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func messageText(parts: [ChatMessagePart]) -> String {
    parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }
}

private struct UserMessage: View {
  let parts: [ChatMessagePart]

  var body: some View {
    VStack(alignment: .trailing, spacing: 8) {
      if attachments.isEmpty == false {
        FileAttachmentsRow(attachments: attachments)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      if text.isEmpty == false {
        UserBubble(text: text)
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }

  private var text: String {
    parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private var attachments: [FileAttachment] {
    parts.enumerated().compactMap { idx, part in
      guard case let .file(file) = part else { return nil }
      return FileAttachment(id: "file-\(idx)", filename: file.filename, mediaType: file.mediaType)
    }
  }
}

#Preview {
  OpenRouterChatDemoView()
}
