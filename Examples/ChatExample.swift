import SwiftUI
import AIKit

// MARK: - Complete Chat Example App

@available(iOS 16.0, macOS 13.0, *)
@main
struct ChatExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct ContentView: View {
    var body: some View {
        TabView {
            BasicChatView()
                .tabItem {
                    Label("Basic Chat", systemImage: "message")
                }
            
            ToolChatView()
                .tabItem {
                    Label("With Tools", systemImage: "wrench.and.screwdriver")
                }
            
            AttachmentsChatView()
                .tabItem {
                    Label("Attachments", systemImage: "paperclip")
                }
            
            PersistentChatView()
                .tabItem {
                    Label("Persistent", systemImage: "externaldrive")
                }
        }
    }
}

// MARK: - Basic Chat Example

@available(iOS 16.0, macOS 13.0, *)
struct BasicChatView: View {
    @UseChat(model: openai("gpt-4o-mini")) var chat
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(chat.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if chat.isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
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
                
                // Input area
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $chat.input)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(chat.status != .ready)
                        .onSubmit {
                            Task {
                                await chat.sendMessage()
                            }
                        }
                    
                    if chat.isLoading {
                        Button(action: { chat.stop() }) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button(action: {
                            Task {
                                await chat.sendMessage()
                            }
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .disabled(chat.input.isEmpty || chat.status != .ready)
                    }
                }
                .padding()
            }
            .navigationTitle("Basic Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        chat.clear()
                    }
                }
            }
        }
    }
}

// MARK: - Chat with Tools Example

@available(iOS 16.0, macOS 13.0, *)
struct ToolChatView: View {
    @UseChat(
        model: openai("gpt-4o-mini"),
        tools: [
            createWeatherTool(),
            createCalculatorTool(),
            createTimeTool()
        ]
    ) var chat
    
    var body: some View {
        NavigationView {
            ChatView(model: openai("gpt-4o-mini"), tools: [
                createWeatherTool(),
                createCalculatorTool(),
                createTimeTool()
            ])
            .navigationTitle("Chat with Tools")
        }
    }
    
    static func createWeatherTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "get_weather",
                description: "Get current weather for a location",
                parameters: .object(properties: [
                    "location": .string(description: "City name, e.g. San Francisco")
                ])
            ),
            execute: { toolCall in
                let location = toolCall.function.parsedArguments?["location"] as? String ?? "Unknown"
                let weather = "Sunny, 72°F in \(location)"
                return ToolResult.success(toolCallId: toolCall.id, text: weather)
            }
        )
    }
    
    static func createCalculatorTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "calculate",
                description: "Perform mathematical calculations",
                parameters: .object(properties: [
                    "expression": .string(description: "Mathematical expression to evaluate")
                ])
            ),
            execute: { toolCall in
                let expression = toolCall.function.parsedArguments?["expression"] as? String ?? ""
                // Simple evaluation (in production, use a proper expression evaluator)
                let result = "Result: 42" // Placeholder
                return ToolResult.success(toolCallId: toolCall.id, text: result)
            }
        )
    }
    
    static func createTimeTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "get_current_time",
                description: "Get the current time",
                parameters: .object(properties: [:])
            ),
            execute: { toolCall in
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                let time = formatter.string(from: Date())
                return ToolResult.success(toolCallId: toolCall.id, text: "Current time: \(time)")
            }
        )
    }
}

// MARK: - Chat with Attachments Example

@available(iOS 16.0, macOS 13.0, *)
struct AttachmentsChatView: View {
    @UseChat(model: openai("gpt-4o")) var chat
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages with attachment support
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading) {
                                MessageBubble(message: message)
                                
                                // Display attachments
                                ForEach(Array(message.attachments.enumerated()), id: \.offset) { index, attachment in
                                    if case .image(let imageContent) = attachment {
                                        Image(uiImage: UIImage(data: imageContent.data) ?? UIImage())
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxHeight: 200)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Selected image preview
                if let selectedImage = selectedImage {
                    HStack {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        Button(action: {
                            self.selectedImage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Input with attachment button
                HStack(spacing: 12) {
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Image(systemName: "photo")
                            .foregroundColor(.blue)
                    }
                    
                    TextField("Type a message...", text: $chat.input)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        Task {
                            await sendWithImage()
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(chat.input.isEmpty && selectedImage == nil)
                }
                .padding()
            }
            .navigationTitle("Chat with Attachments")
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
        }
    }
    
    private func sendWithImage() async {
        var attachments: [ChatAttachment] = []
        
        if let image = selectedImage,
           let data = image.jpegData(compressionQuality: 0.8) {
            attachments.append(.image(ImageContent.jpeg(data)))
        }
        
        if !attachments.isEmpty {
            await chat.sendMessage(withAttachments: attachments)
            selectedImage = nil
        } else {
            await chat.sendMessage()
        }
    }
}

// MARK: - Persistent Chat Example

@available(iOS 16.0, macOS 13.0, *)
struct PersistentChatView: View {
    @UseChat(model: openai("gpt-4o-mini")) var chat
    @State private var showingExportSheet = false
    @State private var exportedMarkdown = ""
    
    var body: some View {
        NavigationView {
            ChatView(model: openai("gpt-4o-mini"))
                .navigationTitle("Persistent Chat")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(action: {
                                exportedMarkdown = chat.exportAsMarkdown()
                                showingExportSheet = true
                            }) {
                                Label("Export as Markdown", systemImage: "square.and.arrow.up")
                            }
                            
                            Button(action: {
                                chat.save(to: "persistent-chat")
                            }) {
                                Label("Save Chat", systemImage: "square.and.arrow.down")
                            }
                            
                            Button(action: {
                                chat.load(from: "persistent-chat")
                            }) {
                                Label("Load Chat", systemImage: "folder")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                chat.clear()
                            }) {
                                Label("Clear Chat", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingExportSheet) {
                    NavigationView {
                        ScrollView {
                            Text(exportedMarkdown)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                        }
                        .navigationTitle("Exported Chat")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingExportSheet = false
                                }
                            }
                        }
                    }
                }
        }
        .chatAutosave(chat, key: "persistent-chat-example")
    }
}

// MARK: - Shared Components

@available(iOS 16.0, macOS 13.0, *)
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)
                
                // Tool calls indicator
                if !message.toolCalls.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                        Text("\(message.toolCalls.count) tool\(message.toolCalls.count == 1 ? "" : "s") used")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Image Picker

#if canImport(UIKit)
import UIKit

@available(iOS 16.0, *)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
#endif