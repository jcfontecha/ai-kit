//
//  StreamingControlDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct StreamingControlDemoView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    
    var body: some View {
        let fallbackModel = "gpt-4o-mini"
        StreamingControlDemoContent(
            model: providerStore.languageModel(fallbackModel),
            providerSummary: providerStore.selectionSummary(fallbackModelId: fallbackModel),
            isUsingRealAPI: providerStore.isUsingRealAPI
        )
        .id(providerStore.selectionIdentity(context: "streaming", fallbackModelId: fallbackModel))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct StreamingControlDemoContent: View {
    let providerSummary: String
    let isUsingRealAPI: Bool
    @UseChat private var chat: AIChat
    
    @State private var streamingSpeed: Double = 1.0
    @State private var showTokenCount = true
    @State private var autoStop = false
    @State private var maxResponseLength = 500
    
    init(model: LanguageModel, providerSummary: String, isUsingRealAPI: Bool) {
        self.providerSummary = providerSummary
        self.isUsingRealAPI = isUsingRealAPI
        _chat = UseChat(
            model: model,
            onFinish: { _, details in
                print("Streaming finished. Tokens used: \(details.usage?.totalTokens ?? 0)")
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            streamingHeader
            statusBar
            messagesSection
            Divider()
            inputSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: isUsingRealAPI
                            ? "Welcome to the streaming control demo! I'm powered by \(providerSummary). Try sending a message and watch it stream in real-time."
                            : "Welcome to the streaming control demo! I'm using the mock provider. Try sending a message and watch the simulated streaming."
                    )
                ])
            }
        }
    }
    
    private var streamingHeader: some View {
        StreamingControlsHeader(
            streamingSpeed: $streamingSpeed,
            showTokenCount: $showTokenCount,
            autoStop: $autoStop,
            maxResponseLength: $maxResponseLength,
            providerSummary: providerSummary,
            isUsingRealAPI: isUsingRealAPI
        )
    }
    
    private var statusBar: some View {
        Group {
            if chat.isLoading {
                StreamingStatusBar(chat: chat, showTokenCount: showTokenCount)
            }
        }
    }
    
    private var messagesSection: some View {
        MessageScrollView(chat: chat)
    }
    
    private var inputSection: some View {
        StreamingInputView(
            chat: chat,
            onLongMessage: {
                chat.input = "Tell me a very long story about AI and the future of technology."
                Task {
                    await chat.sendMessage()
                }
            }
        )
    }
}

struct MessageScrollView: View {
    @ObservedObject var chat: AIChat
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                MessagesList(chat: chat)
                    .padding()
            }
            .onChange(of: chat.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }
}

struct MessagesList: View {
    @ObservedObject var chat: AIChat
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if chat.messages.isEmpty {
                StreamingEmptyStateView()
            }
            
            ForEach(chat.messages) { message in
                StreamingMessageView(
                    message: message,
                    isStreaming: chat.isLoading && message.id == chat.messages.last?.id
                )
                .id(message.id)
            }
            
            if chat.isLoading {
                StreamingIndicatorView()
            }
        }
    }
}

struct StreamingEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Streaming Control")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Watch messages stream in real-time and control the experience")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

struct StreamingStatusBar: View {
    @ObservedObject var chat: AIChat
    let showTokenCount: Bool
    @State private var streamedCharacters = 0
    @State private var streamingTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .scaleEffect(1.2)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: chat.isLoading)
                
                Text("Streaming")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                if showTokenCount {
                    Text("\(streamedCharacters) chars")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("\(String(format: "%.1f", streamingTime))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Stop") {
                    chat.stop()
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: chat.isLoading) { isLoading in
            if isLoading {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }
    
    private func startTimer() {
        streamingTime = 0
        streamedCharacters = chat.messages.last?.content.count ?? 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            streamingTime += 0.1
            streamedCharacters = chat.messages.last?.content.count ?? 0
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct StreamingMessageView: View {
    let message: ChatMessage
    let isStreaming: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isStreaming {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .symbolEffect(.variableColor.iterative)
                }
                
                Spacer()
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            MessageBubbleView(message: message)
            
            // Show streaming cursor for the current message
            if isStreaming && message.role == .assistant {
                HStack {
                    Text("▊")
                        .foregroundColor(.blue)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: isStreaming)
                    
                    Spacer()
                }
                .padding(.leading, 16)
            }
            
            // Message stats
            HStack {
                Text("\(message.content.count) characters")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if message.role == .assistant {
                    Text("Streamed")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct StreamingIndicatorView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        HStack {
            Text("AI is thinking")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Rectangle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 3, height: 12)
                        .scaleEffect(y: 0.3 + 0.7 * abs(sin(phase + Double(index) * 0.5)))
                        .animation(
                            Animation.easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: false),
                            value: phase
                        )
                }
            }
            
            Spacer()
        }
        .onAppear {
            phase = Double.pi * 2
        }
    }
}

struct StreamingInputView: View {
    @ObservedObject var chat: AIChat
    let onLongMessage: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickActionButton(title: "Short", icon: "text.alignleft") {
                        chat.input = "Hi there!"
                        Task { await chat.sendMessage() }
                    }
                    
                    QuickActionButton(title: "Medium", icon: "text.aligncenter") {
                        chat.input = "Tell me about artificial intelligence and machine learning."
                        Task { await chat.sendMessage() }
                    }
                    
                    QuickActionButton(title: "Long", icon: "text.alignright") {
                        onLongMessage()
                    }
                    
                    QuickActionButton(title: "Stream Test", icon: "waveform") {
                        chat.input = "Please write a detailed explanation of how neural networks work, including backpropagation, gradient descent, and the different types of layers."
                        Task { await chat.sendMessage() }
                    }
                }
                .padding(.horizontal)
            }
            
            // Input area
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
            .padding(.horizontal)
        }
        .padding(.bottom)
    }
    
    private func sendMessage() {
        Task {
            await chat.sendMessage()
            isFocused = true
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
    }
}

struct StreamingControlsHeader: View {
    @Binding var streamingSpeed: Double
    @Binding var showTokenCount: Bool
    @Binding var autoStop: Bool
    @Binding var maxResponseLength: Int
    let providerSummary: String
    let isUsingRealAPI: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaming Control Demo")
                .font(.headline)
            Text("Control real-time message streaming")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(isUsingRealAPI ? "Using \(providerSummary)" : "Mock provider active")
                .font(.caption2)
                .foregroundColor(isUsingRealAPI ? .secondary : .orange)
            
            // Streaming controls
            VStack(spacing: 8) {
                HStack {
                    Text("Speed: \(Int(streamingSpeed * 100))%")
                        .font(.caption)
                    Slider(value: $streamingSpeed, in: 0.1...3.0, step: 0.1)
                    Text("3x")
                        .font(.caption)
                }
                
                HStack {
                    Toggle("Show tokens", isOn: $showTokenCount)
                        .font(.caption)
                    Spacer()
                    Toggle("Auto-stop", isOn: $autoStop)
                        .font(.caption)
                }
                
                HStack {
                    Text("Max length: \(maxResponseLength)")
                        .font(.caption)
                    Slider(value: Binding(
                        get: { Double(maxResponseLength) },
                        set: { maxResponseLength = Int($0) }
                    ), in: 50...1000, step: 50)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

#Preview {
    if #available(iOS 16.0, macOS 13.0, *) {
        NavigationView {
            StreamingControlDemoView()
        }
        .environmentObject(ProviderStore())
    } else {
        Text("Requires iOS 16 or macOS 13")
    }
}
