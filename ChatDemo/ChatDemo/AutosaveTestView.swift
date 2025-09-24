//
//  AutosaveTestView.swift
//  ChatDemo
//
//  Test view to understand autosave behavior
//

import SwiftUI
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct AutosaveTestView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    
    var body: some View {
        let fallbackModel = "gpt-4o-mini"
        AutosaveTestContent(
            model: providerStore.languageModel(fallbackModel),
            providerSummary: providerStore.selectionSummary(fallbackModelId: fallbackModel),
            isUsingRealAPI: providerStore.isUsingRealAPI
        )
        .id(providerStore.selectionIdentity(context: "autosave-test", fallbackModelId: fallbackModel))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct AutosaveTestContent: View {
    let providerSummary: String
    let isUsingRealAPI: Bool
    @UseChat private var chat: AIChat
    @State private var logMessages: [String] = []
    
    init(model: LanguageModel, providerSummary: String, isUsingRealAPI: Bool) {
        self.providerSummary = providerSummary
        self.isUsingRealAPI = isUsingRealAPI
        _chat = UseChat(model: model)
    }
    
    var body: some View {
        VStack {
            Text(isUsingRealAPI ? "Using \(providerSummary)" : "Mock provider active")
                .font(.caption2)
                .foregroundColor(isUsingRealAPI ? .secondary : .orange)
                .padding(.top, 8)
            // Log messages
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logMessages, id: \.self) { log in
                        Text(log)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .frame(height: 150)
            .background(Color(.systemGray6))
            
            Divider()
            
            // Chat messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chat.messages) { message in
                        MessageBubbleView(message: message)
                    }
                }
                .padding()
            }
            
            // Input
            ChatInputView(chat: chat)
        }
        .onChange(of: chat.messages.count) { count in
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            logMessages.append("\(timestamp): message count changed to: \(count)")
        }
        .task {
            // Monitor messages in background
            logMessages.append("View appeared, loading chat...")
        }
        .onDisappear {
            logMessages.append("View disappearing, should save now...")
        }
        .chatAutosave(chat, using: UserDefaultsChatPersistence(), chatId: "autosave-test")
        .navigationTitle("Autosave Test")
    }
}

#Preview {
    if #available(iOS 16.0, macOS 13.0, *) {
        NavigationView {
            AutosaveTestView()
        }
        .environmentObject(ProviderStore())
    } else {
        Text("Requires iOS 16 or macOS 13")
    }
}
