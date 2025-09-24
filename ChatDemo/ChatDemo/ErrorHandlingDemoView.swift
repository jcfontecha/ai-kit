//
//  ErrorHandlingDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct ErrorHandlingDemoView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    
    var body: some View {
        let fallbackModel = "gpt-4o-mini"
        ErrorHandlingDemoContent(
            model: providerStore.languageModel(fallbackModel),
            providerSummary: providerStore.selectionSummary(fallbackModelId: fallbackModel),
            isUsingRealAPI: providerStore.isUsingRealAPI
        )
        .id(providerStore.selectionIdentity(context: "error-handling", fallbackModelId: fallbackModel))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct ErrorHandlingDemoContent: View {
    let providerSummary: String
    let isUsingRealAPI: Bool
    @UseChat private var chat: AIChat
    @State private var simulateError = false
    
    init(model: LanguageModel, providerSummary: String, isUsingRealAPI: Bool) {
        self.providerSummary = providerSummary
        self.isUsingRealAPI = isUsingRealAPI
        _chat = UseChat(
            model: model,
            onError: { error in
                print("Chat error occurred: \(error)")
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with error simulation controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Error Handling Demo")
                    .font(.headline)
                Text("Test how the chat handles various error scenarios")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(isUsingRealAPI ? "Using \(providerSummary)" : "Mock provider active")
                    .font(.caption2)
                    .foregroundColor(isUsingRealAPI ? .secondary : .orange)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ErrorSimulationButton(title: "Network Error", icon: "wifi.slash", color: .orange) {
                            simulateNetworkError()
                        }
                        
                        ErrorSimulationButton(title: "Timeout", icon: "clock.badge.exclamationmark", color: .red) {
                            simulateTimeoutError()
                        }
                        
                        ErrorSimulationButton(title: "API Error", icon: "exclamationmark.triangle", color: .purple) {
                            simulateAPIError()
                        }
                        
                        ErrorSimulationButton(title: "Recovery", icon: "arrow.clockwise", color: .green) {
                            recoverFromError()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Error status indicator
            if chat.error != nil {
                ErrorBanner(error: chat.error!, onRetry: {
                    Task { await chat.reload() }
                }, onDismiss: {
                    recoverFromError()
                })
            }
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.orange)
                                Text("Error Handling Demo")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Use the buttons above to simulate different error scenarios")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                        
                        ForEach(chat.messages) { message in
                            MessageWithErrorIndicatorView(message: message)
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
            
            // Input area with error simulation toggle
            VStack(spacing: 0) {
                HStack {
                    Toggle("Simulate errors", isOn: $simulateError)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                ChatInputView(chat: chat)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: isUsingRealAPI
                            ? "Hello! I'm powered by \(providerSummary). This demo shows how AIChat handles errors gracefully. Try the simulation buttons above!"
                            : "Hello! I'm using the mock provider. This demo shows how AIChat handles errors gracefully. Try the simulation buttons above!"
                    )
                ])
            }
        }
    }
    
    private func simulateNetworkError() {
        // Since we can't directly set error state, we'll simulate it through messaging
        let errorMessage = ChatMessage(
            role: .assistant,
            content: "⚠️ Network Error Simulation: The Internet connection appears to be offline. This is a simulated error for demonstration purposes."
        )
        chat.setMessages(chat.messages + [errorMessage])
    }
    
    private func simulateTimeoutError() {
        // Simulate a timeout error through messaging
        let errorMessage = ChatMessage(
            role: .assistant,
            content: "⏱️ Timeout Error Simulation: The request timed out. This would typically happen when the server takes too long to respond."
        )
        chat.setMessages(chat.messages + [errorMessage])
    }
    
    private func simulateAPIError() {
        // Simulate an API error through messaging
        let errorMessage = ChatMessage(
            role: .assistant,
            content: "🚫 API Error Simulation: Rate limit exceeded. In a real scenario, this would prevent further requests until the limit resets."
        )
        chat.setMessages(chat.messages + [errorMessage])
    }
    
    private func recoverFromError() {
        // Clear any error simulation messages
        let recoveryMessage = ChatMessage(
            role: .assistant,
            content: "✅ Error cleared. The chat is ready to continue normally."
        )
        chat.setMessages(chat.messages + [recoveryMessage])
    }
}

struct ErrorSimulationButton: View {
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

struct ErrorBanner: View {
    let error: Error
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Error Occurred")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Retry") {
                    onRetry()
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
                
                Button("Dismiss") {
                    onDismiss()
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .foregroundColor(.gray)
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.red.opacity(0.3)),
            alignment: .bottom
        )
    }
}

struct MessageWithErrorIndicatorView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MessageBubbleView(message: message)
            
            // Show error indicator for failed messages (simulated)
            if message.role == .assistant && message.content.contains("error") {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Message may have errors")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.leading, 16)
            }
            
            // Show delivery status for user messages
            if message.role == .user {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text("Delivered")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                .padding(.trailing, 16)
            }
        }
    }
}

#Preview {
    if #available(iOS 16.0, macOS 13.0, *) {
        NavigationView {
            ErrorHandlingDemoView()
        }
        .environmentObject(ProviderStore())
    } else {
        Text("Requires iOS 16 or macOS 13")
    }
}
