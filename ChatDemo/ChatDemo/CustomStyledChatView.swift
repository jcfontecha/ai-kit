//
//  CustomStyledChatView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

struct CustomStyledChatView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chat
    @State private var selectedTheme: ChatTheme = .default
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: selectedTheme.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom header
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Custom Styled Chat")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(selectedTheme.primaryColor)
                            Text("Beautiful, customizable interface")
                                .font(.caption)
                                .foregroundColor(selectedTheme.secondaryColor)
                        }
                        
                        Spacer()
                        
                        // Theme selector
                        Menu {
                            Button("Default") { selectedTheme = .default }
                            Button("Ocean") { selectedTheme = .ocean }
                            Button("Forest") { selectedTheme = .forest }
                            Button("Sunset") { selectedTheme = .sunset }
                            Button("Dark") { selectedTheme = .dark }
                        } label: {
                            Image(systemName: "paintbrush")
                                .font(.title2)
                                .foregroundColor(selectedTheme.primaryColor)
                        }
                    }
                    
                    StatusIndicator(status: chat.status)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selectedTheme.cardBackground)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                )
                .padding()
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if chat.messages.isEmpty {
                                WelcomeView(theme: selectedTheme)
                                    .padding(.top, 50)
                            }
                            
                            ForEach(chat.messages) { message in
                                StyledMessageView(message: message, theme: selectedTheme)
                                    .id(message.id)
                            }
                            
                            if chat.isLoading {
                                StyledTypingIndicator(theme: selectedTheme)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chat.messages.count) { _ in
                        withAnimation(.spring()) {
                            proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                
                // Custom input
                StyledChatInput(chat: chat, theme: selectedTheme)
                    .padding()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: "Welcome to the custom styled chat! Try different themes using the brush icon above. 🎨"
                    )
                ])
            }
        }
    }
}

struct ChatTheme {
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let backgroundColors: [Color]
    let cardBackground: Color
    let userBubbleColor: Color
    let assistantBubbleColor: Color
    let userTextColor: Color
    let assistantTextColor: Color
    
    static let `default` = ChatTheme(
        primaryColor: .primary,
        secondaryColor: .secondary,
        accentColor: .blue,
        backgroundColors: [Color(.systemBackground), Color(.systemGray6)],
        cardBackground: Color(.systemBackground).opacity(0.9),
        userBubbleColor: .blue,
        assistantBubbleColor: Color(.systemGray5),
        userTextColor: .white,
        assistantTextColor: .primary
    )
    
    static let ocean = ChatTheme(
        primaryColor: .white,
        secondaryColor: .white.opacity(0.8),
        accentColor: .cyan,
        backgroundColors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.3)],
        cardBackground: Color.white.opacity(0.2),
        userBubbleColor: .cyan,
        assistantBubbleColor: Color.white.opacity(0.3),
        userTextColor: .white,
        assistantTextColor: .white
    )
    
    static let forest = ChatTheme(
        primaryColor: .white,
        secondaryColor: .white.opacity(0.8),
        accentColor: .mint,
        backgroundColors: [Color.green.opacity(0.6), Color.mint.opacity(0.3)],
        cardBackground: Color.white.opacity(0.2),
        userBubbleColor: .mint,
        assistantBubbleColor: Color.white.opacity(0.3),
        userTextColor: .white,
        assistantTextColor: .white
    )
    
    static let sunset = ChatTheme(
        primaryColor: .white,
        secondaryColor: .white.opacity(0.8),
        accentColor: .orange,
        backgroundColors: [Color.orange.opacity(0.6), Color.pink.opacity(0.3)],
        cardBackground: Color.white.opacity(0.2),
        userBubbleColor: .orange,
        assistantBubbleColor: Color.white.opacity(0.3),
        userTextColor: .white,
        assistantTextColor: .white
    )
    
    static let dark = ChatTheme(
        primaryColor: .white,
        secondaryColor: .gray,
        accentColor: .purple,
        backgroundColors: [Color.black, Color.purple.opacity(0.2)],
        cardBackground: Color.black.opacity(0.7),
        userBubbleColor: .purple,
        assistantBubbleColor: Color.gray.opacity(0.3),
        userTextColor: .white,
        assistantTextColor: .white
    )
}

struct WelcomeView: View {
    let theme: ChatTheme
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundColor(theme.accentColor)
                .symbolEffect(.bounce)
            
            Text("Custom Styled Chat")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(theme.primaryColor)
            
            Text("Experience beautiful, customizable chat interfaces")
                .font(.subheadline)
                .foregroundColor(theme.secondaryColor)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                ThemePreview(color: .blue, name: "Default")
                ThemePreview(color: .cyan, name: "Ocean")
                ThemePreview(color: .mint, name: "Forest")
                ThemePreview(color: .orange, name: "Sunset")
                ThemePreview(color: .purple, name: "Dark")
            }
            .padding(.top)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(theme.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

struct ThemePreview: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct StyledMessageView: View {
    let message: ChatMessage
    let theme: ChatTheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                HStack {
                    if message.role == .assistant {
                        Avatar(role: message.role, theme: theme)
                    }
                    
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        Text(message.content)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(message.role == .user ? theme.userBubbleColor : theme.assistantBubbleColor)
                                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                            )
                            .foregroundColor(message.role == .user ? theme.userTextColor : theme.assistantTextColor)
                        
                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(theme.secondaryColor)
                    }
                    
                    if message.role == .user {
                        Avatar(role: message.role, theme: theme)
                    }
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: message.id)
    }
}

struct Avatar: View {
    let role: MessageRole
    let theme: ChatTheme
    
    var body: some View {
        Circle()
            .fill(theme.accentColor.opacity(0.8))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: role == .user ? "person.fill" : "sparkles")
                    .font(.caption)
                    .foregroundColor(.white)
            )
    }
}

struct StyledTypingIndicator: View {
    let theme: ChatTheme
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Avatar(role: .assistant, theme: theme)
            
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 8, height: 8)
                        .offset(y: animationOffset)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationOffset
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(theme.assistantBubbleColor)
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            )
            
            Spacer(minLength: 80)
        }
        .onAppear {
            animationOffset = -4
        }
    }
}

struct StyledChatInput: View {
    @ObservedObject var chat: AIChat
    let theme: ChatTheme
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $chat.input)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(theme.cardBackground)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                )
                .foregroundColor(theme.primaryColor)
                .focused($isFocused)
                .disabled(chat.status != .ready)
                .onSubmit {
                    sendMessage()
                }
            
            Button(action: sendMessage) {
                Image(systemName: chat.isLoading ? "stop.circle.fill" : "paperplane.circle.fill")
                    .font(.title2)
                    .foregroundColor(chat.isLoading ? .red : theme.accentColor)
                    .scaleEffect(chat.isLoading ? 1.2 : 1.0)
                    .animation(.spring(), value: chat.isLoading)
            }
            .disabled(chat.input.isEmpty && !chat.isLoading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(theme.cardBackground.opacity(0.8))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -2)
        )
    }
    
    private func sendMessage() {
        if chat.isLoading {
            chat.stop()
        } else {
            Task {
                await chat.sendMessage()
                isFocused = true
            }
        }
    }
}

#Preview {
    CustomStyledChatView()
}