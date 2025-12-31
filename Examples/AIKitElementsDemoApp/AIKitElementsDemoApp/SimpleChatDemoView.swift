import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import AIKit
import AIKitElements

struct SimpleChatDemoView: View {
  @AppStorage(AppSettings.openRouterAPIKeyKey) private var apiKey: String = ""
  @AppStorage(AppSettings.openRouterModelIDKey) private var modelID: String = AppSettings.defaultOpenRouterModelID

  @StateObject private var store = OpenRouterChatStore()
  @State private var text: String = ""
  @State private var attachments: [ChatFilePart] = []
  @State private var isShowingAddSheet: Bool = false

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
      Conversation(messages: store.messages, status: store.status)
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
            store.send(text: message, attachments: attachments)
            attachments.removeAll()
          },
          onStop: { store.stop() },
          onAdd: { isShowingAddSheet = true }
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
    .overlay(alignment: .topTrailing) {
      HStack(spacing: 8) {
        Button("Clear") {
          store.clear()
        }
        .buttonStyle(.bordered)

        if store.status == .streaming || store.status == .submitted {
          Button("Stop") { store.stop() }
            .buttonStyle(.borderedProminent)
        }
      }
      .padding(10)
    }
    base
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
#else
private func imageData(from image: PlatformImage) -> Data? {
  nil
}
#endif

#Preview {
  SimpleChatDemoView()
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
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
