//
//  AdvancedPersistentChatDemoView.swift
//  ChatDemo
//
//  Demonstrates the new ChatPersistence protocol with custom implementations
//

import SwiftUI
import AIKit

struct AdvancedPersistentChatDemoView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o-mini")) var chat
    
    // Different persistence implementations
    @State private var selectedPersistence: PersistenceType = .userDefaults
    @State private var cloudPersistence = CloudChatPersistence()
    @State private var encryptedPersistence = try? EncryptedChatPersistence()
    @State private var versionedPersistence = VersionedChatPersistence()
    @State private var compositePersistence: CompositeChatPersistence?
    
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingExportSheet = false
    @State private var exportedMarkdown = ""
    
    enum PersistenceType: String, CaseIterable {
        case userDefaults = "UserDefaults"
        case file = "File System"
        case cloud = "Cloud Storage"
        case encrypted = "Encrypted"
        case versioned = "Versioned"
        case composite = "Composite"
        
        var icon: String {
            switch self {
            case .userDefaults: return "gear"
            case .file: return "folder"
            case .cloud: return "icloud"
            case .encrypted: return "lock"
            case .versioned: return "doc.badge.clock"
            case .composite: return "square.stack.3d.up"
            }
        }
        
        var color: Color {
            switch self {
            case .userDefaults: return .gray
            case .file: return .blue
            case .cloud: return .cyan
            case .encrypted: return .purple
            case .versioned: return .orange
            case .composite: return .green
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("Advanced Persistence Demo")
                    .font(.headline)
                Text("Choose different storage backends for your chat")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Persistence type selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PersistenceType.allCases, id: \.self) { type in
                            PersistenceButton(
                                type: type,
                                isSelected: selectedPersistence == type
                            ) {
                                selectedPersistence = type
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: saveChat) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    
                    Button(action: loadChat) {
                        Label("Load", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(isLoading)
                    
                    Button(action: deleteChat) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isLoading)
                    
                    Spacer()
                    
                    Button(action: exportChat) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Status indicator
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Working with \(selectedPersistence.rawValue)...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray5))
            }
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            EmptyStateView(persistenceType: selectedPersistence)
                                .padding(.top, 60)
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
                    withAnimation {
                        proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input
            ChatInputView(chat: chat)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupCompositePersistence()
            
            // Show demo message
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: "Welcome to the advanced persistence demo! Try different storage backends:\n\n• **UserDefaults**: Simple, synchronous storage\n• **File System**: Larger capacity, structured storage\n• **Cloud Storage**: Simulated cloud sync with delays\n• **Encrypted**: Secure storage (demo encryption)\n• **Versioned**: Migration-ready storage\n• **Composite**: Local + cloud redundancy\n\nEach backend implements the ChatPersistence protocol!"
                    )
                ])
            }
        }
        .alert("Persistence Operation", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(markdownContent: exportedMarkdown)
        }
    }
    
    private func setupCompositePersistence() {
        if let encryptedPersistence = encryptedPersistence {
            compositePersistence = CompositeChatPersistence(
                local: encryptedPersistence,
                remote: cloudPersistence
            )
        }
    }
    
    private func getCurrentPersistence() -> ChatPersistence {
        switch selectedPersistence {
        case .userDefaults:
            return UserDefaultsChatPersistence()
        case .file:
            return (try? FileChatPersistence()) ?? UserDefaultsChatPersistence()
        case .cloud:
            return cloudPersistence
        case .encrypted:
            return encryptedPersistence ?? UserDefaultsChatPersistence()
        case .versioned:
            return versionedPersistence
        case .composite:
            return compositePersistence ?? UserDefaultsChatPersistence()
        }
    }
    
    private func saveChat() {
        let persistence = getCurrentPersistence()
        let chatId = "demo-\(selectedPersistence.rawValue.lowercased())"
        
        isLoading = true
        Task {
            do {
                try await chat.save(using: persistence, chatId: chatId)
                alertMessage = "✅ Saved \(chat.messages.count) messages using \(selectedPersistence.rawValue)"
                showingAlert = true
            } catch {
                alertMessage = "❌ Save failed: \(error.localizedDescription)"
                showingAlert = true
            }
            isLoading = false
        }
    }
    
    private func loadChat() {
        let persistence = getCurrentPersistence()
        let chatId = "demo-\(selectedPersistence.rawValue.lowercased())"
        
        isLoading = true
        Task {
            do {
                try await chat.load(using: persistence, chatId: chatId)
                alertMessage = "✅ Loaded \(chat.messages.count) messages from \(selectedPersistence.rawValue)"
                showingAlert = true
            } catch {
                alertMessage = "❌ Load failed: \(error.localizedDescription)"
                showingAlert = true
            }
            isLoading = false
        }
    }
    
    private func deleteChat() {
        let persistence = getCurrentPersistence()
        let chatId = "demo-\(selectedPersistence.rawValue.lowercased())"
        
        isLoading = true
        Task {
            do {
                try await persistence.delete(for: chatId)
                alertMessage = "🗑️ Deleted chat from \(selectedPersistence.rawValue)"
                showingAlert = true
            } catch {
                alertMessage = "❌ Delete failed: \(error.localizedDescription)"
                showingAlert = true
            }
            isLoading = false
        }
    }
    
    private func exportChat() {
        exportedMarkdown = chat.exportAsMarkdown()
        showingExportSheet = true
    }
}

struct PersistenceButton: View {
    let type: AdvancedPersistentChatDemoView.PersistenceType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : type.color)
                
                Text(type.rawValue)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? type.color : type.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(type.color, lineWidth: isSelected ? 0 : 1)
            )
        }
    }
}

struct EmptyStateView: View {
    let persistenceType: AdvancedPersistentChatDemoView.PersistenceType
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: persistenceType.icon)
                .font(.system(size: 60))
                .foregroundColor(persistenceType.color)
            
            Text(persistenceType.rawValue)
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }
    
    var description: String {
        switch persistenceType {
        case .userDefaults:
            return "Simple key-value storage, ideal for small data"
        case .file:
            return "File-based storage with no size limits"
        case .cloud:
            return "Simulated cloud storage with sync delays"
        case .encrypted:
            return "Secure storage with encryption (demo only)"
        case .versioned:
            return "Version-aware storage with migration support"
        case .composite:
            return "Redundant storage using both local and cloud"
        }
    }
}

#Preview {
    NavigationView {
        AdvancedPersistentChatDemoView()
    }
}