//
//  AutosaveComparisonView.swift
//  ChatDemo
//
//  Demonstrates different autosave strategies
//

import SwiftUI
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct AutosaveComparisonView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    
    var body: some View {
        let fallbackModel = "gpt-4o-mini"
        AutosaveComparisonContent(
            model: providerStore.languageModel(fallbackModel),
            providerSummary: providerStore.selectionSummary(fallbackModelId: fallbackModel),
            isUsingRealAPI: providerStore.isUsingRealAPI
        )
        .id(providerStore.selectionIdentity(context: "autosave-comparison", fallbackModelId: fallbackModel))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct AutosaveComparisonContent: View {
    struct SaveLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let method: String
        let messageCount: Int
    }
    
    let providerSummary: String
    let isUsingRealAPI: Bool
    @UseChat private var chatOnDisappear: AIChat
    @UseChat private var chatOnChange: AIChat
    @UseChat private var chatDebounced: AIChat
    
    @State private var selectedTab = 0
    @State private var saveLog: [SaveLogEntry] = []
    
    init(model: LanguageModel, providerSummary: String, isUsingRealAPI: Bool) {
        self.providerSummary = providerSummary
        self.isUsingRealAPI = isUsingRealAPI
        _chatOnDisappear = UseChat(model: model)
        _chatOnChange = UseChat(model: model)
        _chatDebounced = UseChat(model: model)
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
                Text(isUsingRealAPI ? "Using \(providerSummary)" : "Mock provider active")
                    .font(.caption2)
                    .foregroundColor(isUsingRealAPI ? .secondary : .orange)
                
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
    if #available(iOS 16.0, macOS 13.0, *) {
        NavigationView {
            AutosaveComparisonView()
        }
        .environmentObject(ProviderStore())
    } else {
        Text("Requires iOS 16 or macOS 13")
    }
}
