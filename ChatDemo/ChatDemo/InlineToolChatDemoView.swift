//
//  InlineToolChatDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/4/25.
//

import SwiftUI
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct InlineToolChatDemoView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    
    var body: some View {
        let fallbackModel = "gpt-4o-mini"
        InlineToolChatDemoContent(
            model: providerStore.languageModel(fallbackModel),
            providerSummary: providerStore.selectionSummary(fallbackModelId: fallbackModel),
            isUsingRealAPI: providerStore.isUsingRealAPI
        )
        .id(providerStore.selectionIdentity(context: "inline-tools", fallbackModelId: fallbackModel))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct InlineToolChatDemoContent: View {
    let providerSummary: String
    let isUsingRealAPI: Bool
    @UseChat private var chat: AIChat
    @State private var selectedTab = 0
    @State private var showingSettings = false
    @State private var showingProfile = false
    
    init(model: LanguageModel, providerSummary: String, isUsingRealAPI: Bool) {
        self.providerSummary = providerSummary
        self.isUsingRealAPI = isUsingRealAPI
        _chat = UseChat(
            model: model,
            tools: [
                NavigationTool.createTool(),
                UIComponentTool.createTool(),
                ActionCardTool.createTool(),
                ProgressIndicatorTool.createTool()
            ]
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with available tools
            VStack(alignment: .leading, spacing: 8) {
                Text("Inline Tool Rendering Demo")
                    .font(.headline)
                Text("AI can render interactive UI components inline")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(isUsingRealAPI ? "Using \(providerSummary)" : "Mock provider active")
                    .font(.caption2)
                    .foregroundColor(isUsingRealAPI ? .secondary : .orange)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ToolChip(name: "Navigation", icon: "arrow.turn.up.right")
                        ToolChip(name: "UI Components", icon: "rectangle.3.group")
                        ToolChip(name: "Action Cards", icon: "rectangle.and.pencil.and.ellipsis")
                        ToolChip(name: "Progress", icon: "chart.bar.fill")
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Messages with inline tool rendering
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "rectangle.3.group")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue)
                                Text("Try asking me to:")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    SuggestionChip(text: "Show me navigation options")
                                    SuggestionChip(text: "Create a progress indicator")
                                    SuggestionChip(text: "Display action cards")
                                    SuggestionChip(text: "Show UI components")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                        }
                        
                        ForEach(chat.messages) { message in
                            InlineToolMessageView(
                                message: message,
                                onNavigate: { destination in
                                    handleNavigation(destination)
                                },
                                onAction: { action in
                                    handleAction(action)
                                }
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
            
            // Input area
            ChatInputView(chat: chat)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: isUsingRealAPI
                            ? "Hello! I'm powered by \(providerSummary). I can render interactive UI components inline. Try asking me to show navigation options, create action cards, or display progress indicators!"
                            : "Hello! I'm using the mock provider. I can render interactive UI components inline. Try asking me to show navigation options, create action cards, or display progress indicators!"
                    )
                ])
            }
        }
    }
    
    private func handleNavigation(_ destination: String) {
        switch destination {
        case "settings":
            showingSettings = true
        case "profile":
            showingProfile = true
        case "tab1":
            selectedTab = 0
        case "tab2":
            selectedTab = 1
        case "tab3":
            selectedTab = 2
        default:
            break
        }
    }
    
    private func handleAction(_ action: String) {
        // Handle various actions triggered by inline tools
        Task {
            await chat.send(content: "Action '\(action)' was triggered!")
        }
    }
}

struct InlineToolMessageView: View {
    let message: ChatMessage
    let onNavigate: (String) -> Void
    let onAction: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group and render content intelligently
            let contentGroups = groupConsecutiveTextContent(message.orderedContent)
            ForEach(Array(contentGroups.enumerated()), id: \.offset) { index, group in
                renderContentGroup(group, at: index)
            }
        }
    }
    
    // Group consecutive text content into single items
    private func groupConsecutiveTextContent(_ content: [MessageContent]) -> [ContentGroup] {
        var groups: [ContentGroup] = []
        var currentTextParts: [String] = []
        
        for item in content {
            switch item {
            case .text(let text):
                currentTextParts.append(text)
            default:
                // Flush any accumulated text
                if !currentTextParts.isEmpty {
                    groups.append(.text(currentTextParts.joined()))
                    currentTextParts = []
                }
                // Add the non-text content
                groups.append(.other(item))
            }
        }
        
        // Flush any remaining text
        if !currentTextParts.isEmpty {
            groups.append(.text(currentTextParts.joined()))
        }
        
        return groups
    }
    
    private enum ContentGroup {
        case text(String)
        case other(MessageContent)
    }
    
    @ViewBuilder
    private func renderContentGroup(_ group: ContentGroup, at index: Int) -> some View {
        switch group {
        case .text(let text):
            MessageBubbleView(message: ChatMessage(
                id: message.id + "_text_\(index)",
                role: message.role,
                content: text,
                timestamp: message.timestamp
            ))
            
        case .other(let content):
            renderContent(content, at: index)
        }
    }
    
    @ViewBuilder
    private func renderContent(_ content: MessageContent, at index: Int) -> some View {
        switch content {
        case .text(let text):
            MessageBubbleView(message: ChatMessage(
                id: message.id + "_text_\(index)",
                role: message.role,
                content: text,
                timestamp: message.timestamp
            ))
            
        case .toolCall(let toolCall):
            InlineToolCallView(
                toolCall: toolCall,
                onNavigate: onNavigate,
                onAction: onAction
            )
            .padding(.leading, message.role == .user ? 60 : 0)
            .padding(.trailing, message.role == .assistant ? 60 : 0)
            
        case .toolResult(let toolResult):
            ToolResultView(toolResult: toolResult)
                .padding(.leading, message.role == .user ? 60 : 0)
                .padding(.trailing, message.role == .assistant ? 60 : 0)
            
        case .image(let imageContent):
            ImageContentView(imageContent: imageContent)
                .padding(.leading, message.role == .user ? 60 : 0)
                .padding(.trailing, message.role == .assistant ? 60 : 0)
            
        case .file(let fileContent):
            FileContentView(fileContent: fileContent)
                .padding(.leading, message.role == .user ? 60 : 0)
                .padding(.trailing, message.role == .assistant ? 60 : 0)
        }
    }
}

struct InlineToolCallView: View {
    let toolCall: ToolCall
    let onNavigate: (String) -> Void
    let onAction: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool call header
            HStack {
                Image(systemName: iconForTool(toolCall.function.name))
                    .foregroundColor(.blue)
                Text(toolCall.function.name)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("Interactive")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
            
            // Render tool-specific UI
            renderToolUI()
        }
    }
    
    @ViewBuilder
    private func renderToolUI() -> some View {
        switch toolCall.function.name {
        case "render_navigation":
            NavigationUIView(onNavigate: onNavigate)
        case "render_ui_component":
            UIComponentView(onAction: onAction)
        case "render_action_card":
            ActionCardView(onAction: onAction)
        case "render_progress_indicator":
            ProgressIndicatorView()
        default:
            EmptyView()
        }
    }
    
    private func iconForTool(_ toolName: String) -> String {
        switch toolName {
        case "render_navigation": return "arrow.turn.up.right"
        case "render_ui_component": return "rectangle.3.group"
        case "render_action_card": return "rectangle.and.pencil.and.ellipsis"
        case "render_progress_indicator": return "chart.bar.fill"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Inline Tool UI Components

struct NavigationUIView: View {
    let onNavigate: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quick Navigation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            VStack(spacing: 8) {
                NavigationButton(
                    title: "Settings",
                    icon: "gear",
                    color: .blue
                ) {
                    onNavigate("settings")
                }
                
                NavigationButton(
                    title: "Profile",
                    icon: "person.circle",
                    color: .green
                ) {
                    onNavigate("profile")
                }
                
                NavigationButton(
                    title: "Dashboard",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                ) {
                    onNavigate("tab1")
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct NavigationButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct UIComponentView: View {
    let onAction: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("UI Components")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack(spacing: 12) {
                ComponentButton(
                    title: "Button",
                    icon: "rectangle.fill",
                    color: .blue
                ) {
                    onAction("button_pressed")
                }
                
                ComponentButton(
                    title: "Toggle",
                    icon: "switch.2",
                    color: .green
                ) {
                    onAction("toggle_switched")
                }
                
                ComponentButton(
                    title: "Slider",
                    icon: "slider.horizontal.3",
                    color: .orange
                ) {
                    onAction("slider_changed")
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ComponentButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActionCardView: View {
    let onAction: (String) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Complete Your Profile")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Add a profile picture and bio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button("Complete") {
                    onAction("complete_profile")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            ProgressView(value: 0.7)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(x: 1, y: 0.5)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ProgressIndicatorView: View {
    @State private var progress: Double = 0.0
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Task Progress")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
            
            HStack {
                Text("Processing data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0)) {
                progress = 0.85
            }
        }
    }
}

// MARK: - Settings and Profile Views

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Preferences") {
                    HStack {
                        Text("Notifications")
                        Spacer()
                        Toggle("", isOn: .constant(true))
                    }
                    
                    HStack {
                        Text("Dark Mode")
                        Spacer()
                        Toggle("", isOn: .constant(false))
                    }
                }
                
                Section("Account") {
                    Text("Manage Account")
                    Text("Privacy Settings")
                    Text("Sign Out")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("John Doe")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Software Developer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 12) {
                    ProfileRow(title: "Email", value: "john@example.com")
                    ProfileRow(title: "Location", value: "San Francisco, CA")
                    ProfileRow(title: "Joined", value: "January 2024")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProfileRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Tool Implementations

struct NavigationTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "render_navigation",
                description: "Render interactive navigation UI with buttons to different app sections",
                parameters: .object(properties: [
                    "destinations": .array(items: .string())
                ], required: ["destinations"])
            ),
            execute: { toolCall in
                let destinations = toolCall.function.parsedArguments?["destinations"] as? [String] ?? []
                let destinationList = destinations.joined(separator: ", ")
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "Navigation UI rendered with destinations: \(destinationList)"
                )
            }
        )
    }
}

struct UIComponentTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "render_ui_component",
                description: "Render interactive UI components like buttons, toggles, and sliders",
                parameters: .object(properties: [
                    "components": .array(items: .string()),
                    "style": .string()
                ], required: ["components"])
            ),
            execute: { toolCall in
                let components = toolCall.function.parsedArguments?["components"] as? [String] ?? []
                let componentList = components.joined(separator: ", ")
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "UI components rendered: \(componentList)"
                )
            }
        )
    }
}

struct ActionCardTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "render_action_card",
                description: "Render an action card with progress and call-to-action button",
                parameters: .object(properties: [
                    "title": .string(),
                    "description": .string(),
                    "progress": .number(),
                    "action": .string()
                ], required: ["title", "description", "action"])
            ),
            execute: { toolCall in
                let title = toolCall.function.parsedArguments?["title"] as? String ?? "Action Card"
                let description = toolCall.function.parsedArguments?["description"] as? String ?? "Complete this action"
                let action = toolCall.function.parsedArguments?["action"] as? String ?? "Complete"
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "Action card rendered: \(title) - \(description) with '\(action)' button"
                )
            }
        )
    }
}

struct ProgressIndicatorTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "render_progress_indicator",
                description: "Render an animated progress indicator showing task completion",
                parameters: .object(properties: [
                    "task": .string(),
                    "progress": .number()
                ], required: ["task"])
            ),
            execute: { toolCall in
                let task = toolCall.function.parsedArguments?["task"] as? String ?? "Processing"
                let progress = toolCall.function.parsedArguments?["progress"] as? Double ?? 0.0
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "Progress indicator rendered for: \(task) at \(Int(progress * 100))%"
                )
            }
        )
    }
}

// MARK: - Additional Content Views

struct ToolResultView: View {
    let toolResult: ToolResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: toolResult.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(toolResult.isError ? .red : .green)
                Text("Tool Result")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text(resultText)
                .font(.subheadline)
                .padding()
                .background((toolResult.isError ? Color.red : Color.green).opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
    
    private var resultText: String {
        switch toolResult.result {
        case .text(let text):
            return text
        case .error(let error):
            return error
        case .json(let data):
            return String(data: data, encoding: .utf8) ?? "JSON Result"
        case .image(_):
            return "Image Result"
        case .file(_):
            return "File Result"
        case .data(_, let mimeType):
            return "Data Result (\(mimeType))"
        }
    }
}

struct ImageContentView: View {
    let imageContent: ImageContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo")
                    .foregroundColor(.blue)
                Text("Image")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 120)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundColor(.gray)
                        Text("Image Content")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                )
        }
        .padding(.vertical, 4)
    }
}

struct FileContentView: View {
    let fileContent: FileContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.orange)
                Text("File")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text(fileContent.filename ?? "Unknown File")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(fileContent.mimeType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    if #available(iOS 16.0, macOS 13.0, *) {
        NavigationView {
            InlineToolChatDemoView()
        }
        .environmentObject(ProviderStore())
    } else {
        Text("Requires iOS 16 or macOS 13")
    }
}
