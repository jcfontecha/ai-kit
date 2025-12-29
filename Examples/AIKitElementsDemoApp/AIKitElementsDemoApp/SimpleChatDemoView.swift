import SwiftUI

import AIKit
import AIKitElements

struct SimpleChatDemoView: View {
  @AppStorage(AppSettings.openRouterAPIKeyKey) private var apiKey: String = ""
  @AppStorage(AppSettings.openRouterModelIDKey) private var modelID: String = AppSettings.defaultOpenRouterModelID

  @StateObject private var store = OpenRouterChatStore()
  @State private var text: String = ""
  @State private var composerHeight: CGFloat = 0

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
  }

  @ViewBuilder
  private var content: some View {
    let base = ZStack {
      Conversation(messages: store.messages, status: store.status, bottomOverlayHeight: composerHeight + 8) { message in
        DemoMessageRow(message: message)
      }
      .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
        store.respondToToolApproval(approvalID: approvalID, approved: approved, reason: reason)
      }

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
    #if os(iOS)
    base
      .safeAreaBar(edge: .bottom) {
        PromptInput(text: $text, status: store.status, onSend: { message in
          store.send(text: message)
          }, onStop: {
            store.stop()
          })
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
          GeometryReader { proxy in
            Color.clear
              .onAppear { composerHeight = proxy.size.height }
              .onChange(of: proxy.size.height) {
                composerHeight = proxy.size.height
              }
          }
        }
      }
    #else
    base
      .promptInputBottomBar(
        text: $text,
        status: store.status,
        height: $composerHeight,
        onSend: { message in
          store.send(text: message)
        },
        onStop: {
          store.stop()
        }
      )
    #endif
  }
}

#Preview {
  SimpleChatDemoView()
}
