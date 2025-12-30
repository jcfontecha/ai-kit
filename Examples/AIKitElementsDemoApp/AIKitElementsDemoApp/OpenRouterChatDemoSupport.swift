import SwiftUI
import Combine
import MarkdownUI

import AIKit
import AIKitOpenRouter
import AIKitElements

@MainActor
final class OpenRouterChatStore: ObservableObject {
  struct Snapshot: Sendable, Equatable {
    var status: ChatStatus
    var messages: [ChatMessage]
    var errorDescription: String?
  }

  @Published var snapshot: Snapshot = .init(status: .ready, messages: [], errorDescription: nil)

  private var chat: ChatStore?
  private var chatUpdates: AnyCancellable?
  private var configuredKey: String = ""
  private var configuredModelID: String = ""

  var messages: [ChatMessage] { snapshot.messages }
  var status: ChatStatus { snapshot.status }
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

  func send(text: String) {
    guard let chat else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }

    chat.sendMessage(trimmed)
  }

  func stop() {
    chat?.stop()
  }

  func regenerate(messageID: String?) {
    chat?.regenerate(messageID: messageID)
  }

  func respondToToolApproval(approvalID: String, approved: Bool, reason: String?) {
    chat?.addToolApprovalResponse(approvalID: approvalID, approved: approved, reason: reason)
  }

  func clear() {
    chatUpdates?.cancel()
    chatUpdates = nil
    chat = nil
    configureIfPossible(apiKey: configuredKey, modelID: configuredModelID)
  }
}

struct DemoMessageRow: View {
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
        AssistantMessage(messageID: message.id, parts: message.parts)
          .assistantMessageToolStatusStrings(demoToolStatusStrings)
          .assistantMessageDefaultToolStatusStrings(.init(
            loading: "Working…",
            success: "Done",
            error: "Error"
          ))
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

  private var demoToolStatusStrings: [String: ToolStatusStrings] {
    [
      "sleep_ms": .init(loading: "Sleeping…", success: "Slept", error: "Sleep failed"),
      "echo_with_delay": .init(loading: "Echoing…", success: "Echoed", error: "Echo failed"),
    ]
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
