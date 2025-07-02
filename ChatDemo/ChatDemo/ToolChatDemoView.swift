//
//  ToolChatDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

struct ToolChatDemoView: View {
    @UseChat(
        model: ProviderManager.shared.languageModel("gpt-4o-mini"),
        tools: [
            WeatherTool.createTool(),
            CalculatorTool.createTool(),
            CurrentTimeTool.createTool()
        ]
    ) var chat
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with available tools
            VStack(alignment: .leading, spacing: 8) {
                Text("Chat with Tools Demo")
                    .font(.headline)
                Text("Available tools: Weather, Calculator, Current Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ToolChip(name: "Weather", icon: "cloud.sun")
                        ToolChip(name: "Calculator", icon: "function")
                        ToolChip(name: "Time", icon: "clock")
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Messages with tool call indicators
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue)
                                Text("Try asking me to:")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    SuggestionChip(text: "What's the weather like?")
                                    SuggestionChip(text: "Calculate 25 * 4 + 10")
                                    SuggestionChip(text: "What time is it?")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                        }
                        
                        ForEach(chat.messages) { message in
                            MessageWithToolsView(message: message)
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
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: "Hello! I can help you with weather, calculations, and telling time. Try asking me to use one of my tools!"
                    )
                ])
            }
        }
    }
}

struct ToolChip: View {
    let name: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(name)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(8)
    }
}

struct SuggestionChip: View {
    let text: String
    
    var body: some View {
        Text("• \(text)")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
}

struct MessageWithToolsView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageBubbleView(message: message)
            
            // Show tool calls if any
            if !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🛠️ Tool calls:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(message.toolCalls, id: \.id) { toolCall in
                        HStack {
                            Image(systemName: iconForTool(toolCall.function.name))
                                .foregroundColor(.blue)
                            Text(toolCall.function.name)
                                .font(.caption)
                            Spacer()
                            Text("Called")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
                .padding(.leading, message.role == .user ? 60 : 0)
                .padding(.trailing, message.role == .assistant ? 60 : 0)
            }
        }
    }
    
    private func iconForTool(_ toolName: String) -> String {
        switch toolName {
        case "get_weather": return "cloud.sun"
        case "calculate": return "function"
        case "get_current_time": return "clock"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Tool Implementations

struct WeatherTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "get_weather",
                description: "Get current weather for a location",
                parameters: .object(properties: [
                    "location": .string()
                ], required: ["location"])
            ),
            execute: { toolCall in
                // Simulate weather API call
                let location = toolCall.function.parsedArguments?["location"] as? String ?? "Unknown"
                let weatherConditions = ["Sunny ☀️", "Cloudy ☁️", "Rainy 🌧️", "Snowy ❄️"]
                let condition = weatherConditions.randomElement()!
                let temperature = Int.random(in: 15...85)
                
                let weatherReport = "Weather in \(location): \(condition), \(temperature)°F"
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: weatherReport
                )
            }
        )
    }
}

struct CalculatorTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "calculate",
                description: "Perform mathematical calculations",
                parameters: .object(properties: [
                    "expression": .string()
                ], required: ["expression"])
            ),
            execute: { toolCall in
                let expression = toolCall.function.parsedArguments?["expression"] as? String ?? ""
                
                // Simple calculation simulation
                let result = evaluateExpression(expression)
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "\(expression) = \(result)"
                )
            }
        )
    }
    
    private static func evaluateExpression(_ expression: String) -> String {
        // Simple demo calculation - in production you'd use a proper expression evaluator
        let cleaned = expression.replacingOccurrences(of: " ", with: "")
        
        if cleaned.contains("+") {
            let parts = cleaned.components(separatedBy: "+")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) {
                return String(format: "%.2f", a + b)
            }
        } else if cleaned.contains("*") {
            let parts = cleaned.components(separatedBy: "*")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) {
                return String(format: "%.2f", a * b)
            }
        } else if cleaned.contains("-") {
            let parts = cleaned.components(separatedBy: "-")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) {
                return String(format: "%.2f", a - b)
            }
        } else if cleaned.contains("/") {
            let parts = cleaned.components(separatedBy: "/")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
                return String(format: "%.2f", a / b)
            }
        }
        
        return "42" // Default demo result
    }
}

struct CurrentTimeTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "get_current_time",
                description: "Get the current time and date",
                parameters: .object(properties: [:], required: [])
            ),
            execute: { toolCall in
                let formatter = DateFormatter()
                formatter.dateStyle = .full
                formatter.timeStyle = .medium
                
                let currentTime = formatter.string(from: Date())
                
                return ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "Current time: \(currentTime)"
                )
            }
        )
    }
}

#Preview {
    NavigationView {
        ToolChatDemoView()
    }
}