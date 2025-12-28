import SwiftUI
import Combine
import MarkdownUI

import AIKitOpenRouter
import AIKit
import AIKitElements

struct OpenRouterChatDemoView: View {
  @AppStorage(AppSettings.openRouterAPIKeyKey) private var apiKey: String = ""
  @AppStorage(AppSettings.openRouterModelIDKey) private var modelID: String = AppSettings.defaultOpenRouterModelID

  @StateObject private var store = OpenRouterChatStore()
  @State private var text: String = ""
  @State private var composerHeight: CGFloat = 0

  var body: some View {
    ZStack {
      Conversation(messages: store.messages, bottomOverlayHeight: composerHeight) { message in
        DemoMessageRow(message: message)
      }
      .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
        Task { await store.respondToToolApproval(approvalID: approvalID, approved: approved, reason: reason) }
      }

      if store.messages.isEmpty {
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

        if store.status == .streaming || store.status == .submitted {
          Button("Stop") { Task { await store.stop() } }
            .buttonStyle(.borderedProminent)
        }
      }
      .padding(10)
    }
    .promptInputBottomBar(
      text: $text,
      status: store.status,
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

  private var chat: ChatStore?
  private var chatUpdates: AnyCancellable?
  private var configuredKey: String = ""
  private var configuredModelID: String = ""

  var messages: [ChatMessage] { snapshot.messages }
  var status: ChatSessionStatus { snapshot.status }
  var errorDescription: String? { snapshot.errorDescription }

  func configureIfPossible(apiKey: String, modelID: String) {
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)

    if apiKey.isEmpty || modelID.isEmpty {
      chatUpdates?.cancel()
      chatUpdates = nil
      chat = nil
      configuredKey = ""
      configuredModelID = ""
      snapshot = .init(
        status: .ready,
        messages: DemoContent.initialMessages,
        errorDescription: apiKey.isEmpty ? "Set an OpenRouter API key in Settings to use this demo." : "Set a model ID in Settings."
      )
      return
    }

    guard apiKey != configuredKey || modelID != configuredModelID || chat == nil else {
      return
    }

    configuredKey = apiKey
    configuredModelID = modelID

    chatUpdates?.cancel()
    chatUpdates = nil

    let provider = createOpenRouter(.init(apiKey: apiKey))
    let model = provider.chat(modelID)
    let chat = ChatStore(
      model: model,
      tools: demoTools(),
      initialMessages: DemoContent.initialMessages
    )
    self.chat = chat
    snapshot = .init(status: chat.status, messages: chat.messages, errorDescription: chat.errorDescription)
    chatUpdates = chat.objectWillChange.sink { [weak self] _ in
      guard let self, let chat = self.chat else { return }
      self.snapshot = .init(status: chat.status, messages: chat.messages, errorDescription: chat.errorDescription)
    }
  }

  func send(text: String) async {
    guard let chat else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }

    chat.sendMessage(trimmed)
  }

  func stop() async {
    chat?.stop()
  }

  func respondToToolApproval(approvalID: String, approved: Bool, reason: String?) async {
    chat?.addToolApprovalResponse(approvalID: approvalID, approved: approved, reason: reason)
  }

  func clear() async {
    chatUpdates?.cancel()
    chatUpdates = nil
    chat = nil
    configureIfPossible(apiKey: configuredKey, modelID: configuredModelID)
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
        AssistantMessage(
          parts: message.parts,
          toolDefaultStatusStrings: .init(
            loading: "Loading",
            success: "Completed",
            error: "Error"
          ),
          assistantReasoningText: { text in
            Markdown(text)
              .markdownTextStyle { ForegroundColor(.secondary) }
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        ) { text in
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
