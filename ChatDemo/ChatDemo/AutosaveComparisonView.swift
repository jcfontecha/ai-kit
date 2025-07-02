//
//  AutosaveComparisonView.swift
//  ChatDemo
//
//  Demonstrates different autosave strategies
//

import SwiftUI
import AIKit

struct AutosaveComparisonView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chatOnDisappear
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chatOnChange
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chatDebounced
    
    @State private var selectedTab = 0
    @State private var saveLog: [SaveLogEntry] = []
    
    struct SaveLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let method: String
        let messageCount: Int
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Autosave Comparison")
                    .font(.headline)
                Text("Compare different autosave strategies")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Strategy", selection: $selectedTab) {
                    Text("On Disappear").tag(0)
                    Text("On Change").tag(1)
                    Text("Debounced").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Save log
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(saveLog) { entry in
                        HStack {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(entry.method)
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Spacer()
                            
                            Text("\(entry.messageCount) msgs")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .frame(height: 100)
            .background(Color(.systemGray5))
            
            Divider()
            
            // Chat views
            TabView(selection: $selectedTab) {
                ChatTabContent(
                    chat: chatOnDisappear,
                    title: "Saves only when view disappears",
                    onSave: { count in
                        saveLog.append(SaveLogEntry(
                            timestamp: Date(),
                            method: "OnDisappear",
                            messageCount: count
                        ))
                    }
                )
                .tag(0)
                .chatAutosave(
                    chatOnDisappear,
                    using: LoggingPersistence(
                        wrapped: UserDefaultsChatPersistence(),
                        onSave: { messages in
                            saveLog.append(SaveLogEntry(
                                timestamp: Date(),
                                method: "OnDisappear",
                                messageCount: messages.count
                            ))
                        }
                    ),
                    chatId: "comparison-disappear"
                )
                
                ChatTabContent(
                    chat: chatOnChange,
                    title: "Saves after each message",
                    onSave: { count in
                        saveLog.append(SaveLogEntry(
                            timestamp: Date(),
                            method: "OnChange",
                            messageCount: count
                        ))
                    }
                )
                .tag(1)
                .chatAutosaveEnhanced(
                    chatOnChange,
                    using: LoggingPersistence(
                        wrapped: UserDefaultsChatPersistence(),
                        onSave: { messages in
                            saveLog.append(SaveLogEntry(
                                timestamp: Date(),
                                method: "OnChange",
                                messageCount: messages.count
                            ))
                        }
                    ),
                    chatId: "comparison-change"
                )
                
                ChatTabContent(
                    chat: chatDebounced,
                    title: "Saves with 2s debounce",
                    onSave: { count in
                        saveLog.append(SaveLogEntry(
                            timestamp: Date(),
                            method: "Debounced",
                            messageCount: count
                        ))
                    }
                )
                .tag(2)
                .chatAutosaveDebounced(
                    chatDebounced,
                    using: LoggingPersistence(
                        wrapped: UserDefaultsChatPersistence(),
                        onSave: { messages in
                            saveLog.append(SaveLogEntry(
                                timestamp: Date(),
                                method: "Debounced",
                                messageCount: messages.count
                            ))
                        }
                    ),
                    chatId: "comparison-debounced",
                    debounceInterval: 2.0
                )
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear Log") {
                    saveLog.removeAll()
                }
            }
        }
    }
}

struct ChatTabContent: View {
    let chat: AIChat
    let title: String
    let onSave: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray5))
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chat.messages) { message in
                        MessageBubbleView(message: message)
                    }
                    
                    if chat.isLoading {
                        TypingIndicatorView()
                    }
                }
                .padding()
            }
            
            Divider()
            
            ChatInputView(chat: chat)
        }
    }
}

// Logging wrapper for persistence
struct LoggingPersistence: ChatPersistence {
    let wrapped: ChatPersistence
    let onSave: ([ChatMessage]) -> Void
    
    func save(_ messages: [ChatMessage], for chatId: String) async throws {
        onSave(messages)
        try await wrapped.save(messages, for: chatId)
    }
    
    func load(for chatId: String) async throws -> [ChatMessage] {
        try await wrapped.load(for: chatId)
    }
    
    func delete(for chatId: String) async throws {
        try await wrapped.delete(for: chatId)
    }
}

#Preview {
    NavigationView {
        AutosaveComparisonView()
    }
}