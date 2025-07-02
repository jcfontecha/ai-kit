//
//  BasicChatDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

struct BasicChatDemoView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chat
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Basic AIChat Demo")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text("Experience the @UseChat property wrapper")
                        Text(ProviderManager.shared.isUsingRealAPI ? "• OpenAI" : "• Mock")
                            .foregroundColor(ProviderManager.shared.isUsingRealAPI ? .green : .orange)
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                StatusIndicator(status: chat.status)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                Text("Start a conversation!")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("This demo uses a mock provider for testing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                        
                        ForEach(chat.messages) { message in
                            MessageBubbleView(message: message)
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
            
            // Error display
            if let error = chat.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Retry") {
                        Task {
                            await chat.reload()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
            }
            
            // Input area
            ChatInputView(chat: chat)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Add a welcome message
            if chat.messages.isEmpty {
                let welcomeMessage = ProviderManager.shared.isUsingRealAPI
                    ? "Hello! I'm powered by OpenAI's GPT-4o-mini. This demo uses the @UseChat property wrapper with a real AI model. Ask me anything!"
                    : "Hello! I'm your AI assistant using a mock provider. This is a demo of the @UseChat property wrapper. Try asking me anything!"
                
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: welcomeMessage
                    )
                ])
            }
        }
    }
}

struct StatusIndicator: View {
    let status: ChatStatus
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .ready: return .green
        case .submitted, .streaming: return .orange
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .ready: return "Ready"
        case .submitted: return "Sending..."
        case .streaming: return "Streaming"
        case .error: return "Error"
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.role == .user ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

struct TypingIndicatorView: View {
    @State private var dotCount = 0
    
    var body: some View {
        HStack {
            Text("AI is typing\(String(repeating: ".", count: dotCount))")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

struct ChatInputView: View {
    @ObservedObject var chat: AIChat
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $chat.input)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(chat.status != .ready)
                .focused($isFocused)
                .onSubmit {
                    sendMessage()
                }
            
            Group {
                if chat.isLoading {
                    Button("Stop") {
                        chat.stop()
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Send") {
                        sendMessage()
                    }
                    .disabled(chat.input.isEmpty || chat.status != .ready)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func sendMessage() {
        Task {
            await chat.sendMessage()
            isFocused = true
        }
    }
}

#Preview {
    NavigationView {
        BasicChatDemoView()
    }
}