//
//  PersistentChatDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

struct PersistentChatDemoView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chat
    @State private var showingExportSheet = false
    @State private var exportedMarkdown = ""
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with persistence controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Persistent Chat Demo")
                    .font(.headline)
                Text("Your conversation is automatically saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ActionButton(title: "Save", icon: "square.and.arrow.down", color: .blue) {
                            saveChat()
                        }
                        
                        ActionButton(title: "Load", icon: "folder", color: .green) {
                            loadChat()
                        }
                        
                        ActionButton(title: "Export", icon: "square.and.arrow.up", color: .purple) {
                            exportChat()
                        }
                        
                        ActionButton(title: "Clear", icon: "trash", color: .red) {
                            clearChat()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "externaldrive")
                                    .font(.system(size: 60))
                                    .foregroundColor(.purple)
                                Text("Persistent Chat")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Your messages are automatically saved and can be restored later")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                        
                        ForEach(chat.messages) { message in
                            MessageWithMetadataView(message: message)
                                .id(message.id)
                        }
                        
                        if chat.isLoading {
                            TypingIndicatorView()
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Chat stats
            if !chat.messages.isEmpty {
                HStack {
                    Text("\(chat.messages.count) messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let lastMessage = chat.messages.last {
                        Text("Last: \(lastMessage.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
            }
            
            // Input area
            ChatInputView(chat: chat)
        }
        .navigationBarTitleDisplayMode(.inline)
        .chatAutosave(chat, key: "persistent-chat-demo")
        .sheet(isPresented: $showingExportSheet) {
            ExportView(markdownContent: exportedMarkdown)
        }
        .alert("Chat Saved", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveMessage)
        }
        .onAppear {
            // Try to load existing chat
            loadChat()
            
            // If no existing chat, show welcome message
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: "Welcome to the persistent chat demo! Your conversation will be automatically saved. Try the save/load buttons above!"
                    )
                ])
            }
        }
    }
    
    private func saveChat() {
        chat.save(to: "persistent-chat-demo")
        saveMessage = "Chat saved with \(chat.messages.count) messages"
        showingSaveAlert = true
    }
    
    private func loadChat() {
        chat.load(from: "persistent-chat-demo")
    }
    
    private func exportChat() {
        exportedMarkdown = chat.exportAsMarkdown()
        showingExportSheet = true
    }
    
    private func clearChat() {
        chat.clear()
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(8)
        }
    }
}

struct MessageWithMetadataView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("ID: \(message.id.prefix(8))...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospaced()
            }
            
            MessageBubbleView(message: message)
            
            HStack {
                Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !message.toolCalls.isEmpty {
                    Text("\(message.toolCalls.count) tool calls")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct ExportView: View {
    let markdownContent: String
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(markdownContent)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Exported Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Copy") {
                        UIPasteboard.general.string = markdownContent
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        PersistentChatDemoView()
    }
}