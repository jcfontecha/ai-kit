//
//  OpenRouterChatDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/11/25.
//

import SwiftUI
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct OpenRouterChatDemoView: View {
    private let state: ProviderState
    
    private struct ProviderState {
        let model: LanguageModel?
        let providerDescription: String
        let isConfigured: Bool
    }
    
    init() {
        if let apiKey = ConfigLoader.loadOpenRouterAPIKey() {
            let provider = OpenRouterProvider(
                apiKey: apiKey,
                compatibility: .strict,
                headers: ["HTTP-Referer": "AIKit Demo"]
            )
            let model = provider
                .languageModel("anthropic/claude-3.5-sonnet")
                .temperature(0.6)
            state = ProviderState(
                model: model,
                providerDescription: "OpenRouter • anthropic/claude-3.5-sonnet (strict mode)",
                isConfigured: true
            )
        } else {
            state = ProviderState(model: nil, providerDescription: "Missing OPENROUTER_API_KEY", isConfigured: false)
        }
    }
    
    var body: some View {
        Group {
            if let model = state.model {
                OpenRouterChatExperienceView(model: model, providerDescription: state.providerDescription)
            } else {
                MissingOpenRouterConfigView()
            }
        }
        .navigationTitle("OpenRouter Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct OpenRouterChatExperienceView: View {
    let providerDescription: String
    @UseChat private var chat: AIChat
    
    init(model: LanguageModel, providerDescription: String) {
        self.providerDescription = providerDescription
        self._chat = UseChat(model: model)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            chatTranscript
            footer
        }
        .onAppear(perform: prepareWelcomeMessage)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenRouter Playground")
                    .font(.headline)
                Text(providerDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            StatusIndicator(status: chat.status)
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        OpenRouterEmptyStateView()
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
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }
    
    private var footer: some View {
        VStack(spacing: 0) {
            if let error = chat.error {
                ErrorBannerView(error: error) {
                    Task { await chat.reload() }
                }
                .transition(.opacity)
            }
            
            Divider()
            ChatInputView(chat: chat)
        }
    }
    
    private func prepareWelcomeMessage() {
        guard chat.messages.isEmpty else { return }
        let welcome = "Hello from OpenRouter! This chat is routed through anthropic/claude-3.5-sonnet. Ask anything to see responses proxied through OpenRouter."
        chat.setMessages([
            ChatMessage(
                role: .assistant,
                content: welcome
            )
        ])
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct OpenRouterEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 56))
                .foregroundColor(.blue)
            Text("Connected to OpenRouter")
                .font(.title3)
            Text("Send a message to test cross-provider routing and reasoning support.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct ErrorBannerView: View {
    let error: Error
    let retry: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundColor(.red)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: retry)
                .font(.caption)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}

private struct MissingOpenRouterConfigView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
                Text("OpenRouter API Key Required")
                    .font(.title2)
                    .bold()
                Text("Add your OpenRouter API key to `Config.plist` under the `OPENROUTER_API_KEY` entry or set it via environment configuration before running the demo.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Config.plist snippet:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("<key>OPENROUTER_API_KEY</key>\n<string>sk-or-...</string>")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                Text("The rest of the demo remains available using the mock providers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
    }
}

#if DEBUG
@available(iOS 16.0, macOS 13.0, *)
#Preview {
    NavigationView {
        OpenRouterChatDemoView()
    }
}
#endif
