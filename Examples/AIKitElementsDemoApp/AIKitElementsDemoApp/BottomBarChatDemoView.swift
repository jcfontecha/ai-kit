import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import AIKit
import AIKitElements

struct BottomBarChatDemoView: View {
  @AppStorage(AppSettings.openRouterAPIKeyKey) private var apiKey: String = ""
  @AppStorage(AppSettings.openRouterModelIDKey) private var modelID: String = AppSettings.defaultOpenRouterModelID

  @StateObject private var store = OpenRouterChatStore()
  @State private var text: String = ""
  @State private var attachments: [ChatFilePart] = []
  @State private var isShowingAddSheet: Bool = false
  @State private var sendTrigger: Int = 0
  @State private var editingUserMessageID: String? = nil

  var body: some View {
    content
      .task {
        store.configureIfPossible(apiKey: apiKey, modelID: modelID)
      }
      .onChange(of: apiKey) { _, _ in
        store.configureIfPossible(apiKey: apiKey, modelID: modelID)
      }
      .onChange(of: modelID) { _, _ in
        store.configureIfPossible(apiKey: apiKey, modelID: modelID)
      }
      .sheet(isPresented: $isShowingAddSheet) {
        MockAddSheet()
      }
  }

  @ViewBuilder
  private var content: some View {
    let base = ZStack {
      Conversation(messages: store.messages, status: store.status, sendTrigger: sendTrigger)
        .conversationAnchorsNewUserMessagesToTop(true)
        .conversationDebugOverlayEnabled(true)
        .conversationOnEditUserMessage { message in
          guard message.role == .user else { return }
          editingUserMessageID = message.id
          text = userText(from: message)
          attachments = userAttachments(from: message)
        }
        .assistantMessageToolRenderer("sleep_ms") { context in
          ToolPartReasoningView(
            tool: context.tool,
            icon: Image(systemName: "timer"),
            sendApproval: context.sendApproval,
            statusStrings: .init(loading: "Sleeping…", success: "Slept", error: "Sleep failed")
          )
        }
        .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
          store.respondToToolApproval(approvalID: approvalID, approved: approved, reason: reason)
        }
        .assistantMessageOnRegenerate { messageID in
          store.regenerate(messageID: messageID)
        }
        .chatComposer(
          text: $text,
          status: store.status,
          attachments: attachments,
          editing: promptEditingContext,
          onPasteImages: { images in
            attachments.append(contentsOf: images.compactMap { image in
              guard let data = imageData(from: image) else { return nil }
              return ChatFilePart(
                data: .data(data),
                filename: nil,
                mediaType: "image/png"
              )
            })
          },
          showsScrollToLatestButton: true,
          onSend: { message in
            sendTrigger += 1
            store.send(text: message, attachments: attachments)
            attachments.removeAll()
          },
          onStop: { store.stop() },
          onAdd: { isShowingAddSheet = true },
          expandedBottomBar: {
            HStack(spacing: 8) {
              circleButton(symbol: "plus") { isShowingAddSheet = true }
              circleButton(symbol: "magnifyingglass") {}
              circleButton(symbol: "mic.fill") {}
            }
          }
        )

      if store.messages.isEmpty {
        Text("Start a conversation")
          .font(.headline)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .overlay(alignment: .top) {
      if let error = store.errorDescription {
        Text(error)
          .font(.caption)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(Color.red.opacity(0.85))
      }
    }
    base
  }

  private var promptEditingContext: PromptInputEditingContext? {
    guard let messageID = editingUserMessageID else { return nil }
    return .init(
      title: "Editing",
      onCancel: {
        editingUserMessageID = nil
        text = ""
        attachments.removeAll()
      },
      onCommit: { updatedText in
        sendTrigger += 1
        store.replaceUserMessage(messageID: messageID, text: updatedText, attachments: attachments)
        editingUserMessageID = nil
        attachments.removeAll()
      }
    )
  }

  private func circleButton(symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        .frame(width: 34, height: 34)
        .foregroundStyle(.primary)
        .background(Color.gray.opacity(0.15), in: .circle)
    }
    .buttonStyle(.plain)
  }

  private func userText(from message: ChatMessage) -> String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private func userAttachments(from message: ChatMessage) -> [ChatFilePart] {
    message.parts.compactMap { part in
      guard case let .file(file) = part else { return nil }
      return file
    }
  }
}

#if os(iOS)
private func imageData(from image: UIImage) -> Data? {
  image.pngData()
}
#elseif os(macOS)
private func imageData(from image: NSImage) -> Data? {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff) else { return nil }
  return rep.representation(using: .png, properties: [:])
}
#endif

#Preview {
  BottomBarChatDemoView()
}

private struct MockAddSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Mock actions") {
          Button("Pick photo (mock)") {}
          Button("Pick file (mock)") {}
          Button("Take photo (mock)") {}
        }

        Section {
          Button("Close") { dismiss() }
        }
      }
      .navigationTitle("Add")
#if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
#endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
