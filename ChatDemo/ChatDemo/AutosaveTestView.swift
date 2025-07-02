//
//  AutosaveTestView.swift
//  ChatDemo
//
//  Test view to understand autosave behavior
//

import SwiftUI
import AIKit

struct AutosaveTestView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chat
    @State private var logMessages: [String] = []
    
    var body: some View {
        VStack {
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
        .onChange(of: chat.messages) { messages in
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            logMessages.append("\(timestamp): messages changed, count: \(messages.count)")
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
    NavigationView {
        AutosaveTestView()
    }
}