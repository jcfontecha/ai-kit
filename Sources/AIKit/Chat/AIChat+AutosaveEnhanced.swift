//
//  AIChat+AutosaveEnhanced.swift
//  AIKit
//
//  Enhanced autosave functionality that saves after each message
//

import Foundation
#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public extension View {
    /// Enhanced autosave that saves after each message is added
    /// - Parameters:
    ///   - chat: The AIChat instance to persist
    ///   - persistence: The persistence provider to use
    ///   - chatId: Unique identifier for this chat session
    ///   - saveOnChange: If true, saves after each message change (default: true)
    func chatAutosaveEnhanced(
        _ chat: AIChat,
        using persistence: ChatPersistence,
        chatId: String,
        saveOnChange: Bool = true
    ) -> some View {
        self
            .task {
                // Load on appear
                try? await chat.load(using: persistence, chatId: chatId)
            }
            .onChange(of: chat.messages.count) { _ in
                if saveOnChange {
                    // Save whenever message count changes
                    Task {
                        try? await chat.save(using: persistence, chatId: chatId)
                    }
                }
            }
            .onDisappear {
                // Final save on disappear
                Task {
                    try? await chat.save(using: persistence, chatId: chatId)
                }
            }
    }
    
    /// Autosave with debouncing to reduce save frequency
    /// - Parameters:
    ///   - chat: The AIChat instance to persist
    ///   - persistence: The persistence provider to use
    ///   - chatId: Unique identifier for this chat session
    ///   - debounceInterval: Time to wait before saving (default: 2 seconds)
    func chatAutosaveDebounced(
        _ chat: AIChat,
        using persistence: ChatPersistence,
        chatId: String,
        debounceInterval: TimeInterval = 2.0
    ) -> some View {
        ChatAutosaveDebouncer(
            chat: chat,
            persistence: persistence,
            chatId: chatId,
            debounceInterval: debounceInterval,
            content: self
        )
    }
}

/// Helper view that implements debounced autosave
@available(iOS 16.0, macOS 13.0, *)
private struct ChatAutosaveDebouncer<Content: View>: View {
    let chat: AIChat
    let persistence: ChatPersistence
    let chatId: String
    let debounceInterval: TimeInterval
    let content: Content
    
    @State private var saveTask: Task<Void, Never>?
    
    var body: some View {
        content
            .task {
                // Load on appear
                try? await chat.load(using: persistence, chatId: chatId)
            }
            .onChange(of: chat.messages.count) { _ in
                // Cancel previous save task
                saveTask?.cancel()
                
                // Schedule new save task
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
                    
                    if !Task.isCancelled {
                        try? await chat.save(using: persistence, chatId: chatId)
                    }
                }
            }
            .onDisappear {
                // Cancel pending save and do immediate save
                saveTask?.cancel()
                Task {
                    try? await chat.save(using: persistence, chatId: chatId)
                }
            }
    }
}
#endif