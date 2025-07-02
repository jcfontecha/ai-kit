//
//  MessageManagementDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

struct MessageManagementDemoView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chat
    @State private var selectedMessage: ChatMessage?
    @State private var showingEditAlert = false
    @State private var editingText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Message Management Demo")
                    .font(.headline)
                Text("Edit, delete, and manipulate messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ActionButton(title: "Add System", icon: "gear", color: .gray) {
                            addSystemMessage()
                        }
                        
                        ActionButton(title: "Clear All", icon: "trash", color: .red) {
                            chat.clear()
                        }
                        
                        ActionButton(title: "Regenerate", icon: "arrow.clockwise", color: .blue) {
                            Task { await chat.reload() }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Messages with management controls
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 60))
                                    .foregroundColor(.orange)
                                Text("Message Management")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Long press messages to edit or delete them")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                        
                        ForEach(chat.messages) { message in
                            ManageableMessageView(
                                message: message,
                                onEdit: { editMessage(message) },
                                onDelete: { deleteMessage(message) }
                            )
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
            
            // Message statistics
            if !chat.messages.isEmpty {
                VStack(spacing: 4) {
                    HStack {
                        Text("Total: \(chat.messages.count)")
                        Spacer()
                        Text("User: \(chat.messages.filter { $0.role == .user }.count)")
                        Spacer()
                        Text("Assistant: \(chat.messages.filter { $0.role == .assistant }.count)")
                        Spacer()
                        Text("System: \(chat.messages.filter { $0.role == .system }.count)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if let lastUser = chat.lastUserMessage, let lastAssistant = chat.lastAssistantMessage {
                        HStack {
                            Text("Last user: \(String(lastUser.content.prefix(20)))...")
                            Spacer()
                            Text("Last AI: \(String(lastAssistant.content.prefix(20)))...")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
            }
            
            // Input area
            ChatInputView(chat: chat)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Edit Message", isPresented: $showingEditAlert) {
            TextField("Message content", text: $editingText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let message = selectedMessage {
                    chat.editMessage(id: message.id, newContent: editingText)
                }
            }
        } message: {
            Text("Edit the message content:")
        }
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .system,
                        content: "You are a helpful assistant. This is a system message that sets your behavior."
                    ),
                    ChatMessage(
                        role: .assistant,
                        content: "Hello! This is the message management demo. You can edit and delete messages by long-pressing them. Try sending some messages!"
                    )
                ])
            }
        }
    }
    
    private func addSystemMessage() {
        let systemMessage = ChatMessage(
            role: .system,
            content: "System message added at \(Date().formatted(date: .omitted, time: .shortened))"
        )
        var newMessages = chat.messages
        newMessages.insert(systemMessage, at: 0)
        chat.setMessages(newMessages)
    }
    
    private func editMessage(_ message: ChatMessage) {
        selectedMessage = message
        editingText = message.content
        showingEditAlert = true
    }
    
    private func deleteMessage(_ message: ChatMessage) {
        chat.removeMessage(id: message.id)
    }
}

struct ManageableMessageView: View {
    let message: ChatMessage
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RoleIndicator(role: message.role)
                Spacer()
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            MessageBubbleView(message: message)
                .contextMenu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
            
            HStack {
                Text("ID: \(message.id.prefix(8))...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospaced()
                
                Spacer()
                
                Text("\(message.content.count) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct RoleIndicator: View {
    let role: MessageRole
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(roleColor)
                .frame(width: 8, height: 8)
            Text(role.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(roleColor)
        }
    }
    
    private var roleColor: Color {
        switch role {
        case .user: return .blue
        case .assistant: return .green
        case .system: return .orange
        case .tool: return .purple
        }
    }
}

#Preview {
    NavigationView {
        MessageManagementDemoView()
    }
}