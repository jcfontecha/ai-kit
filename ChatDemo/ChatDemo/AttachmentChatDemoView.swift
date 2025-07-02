//
//  AttachmentChatDemoView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI
import AIKit

struct AttachmentChatDemoView: View {
    @UseChat(model: ProviderManager.shared.languageModel("gpt-4o")) var chat
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showingDocumentPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("File Attachments Demo")
                    .font(.headline)
                Text("Send images and files with your messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            
            // Messages with attachment support
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                                Text("Send files and images!")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Tap the attachment buttons below to add files to your messages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                        
                        ForEach(chat.messages) { message in
                            MessageWithAttachmentsView(message: message, chat: chat)
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
            
            // Selected image preview
            if let selectedImage = selectedImage {
                HStack {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading) {
                        Text("Selected Image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Ready to send")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Button("Remove") {
                        self.selectedImage = nil
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
            
            Divider()
            
            // Input area with attachment buttons
            AttachmentInputView(
                chat: chat,
                selectedImage: $selectedImage,
                showingImagePicker: $showingImagePicker,
                showingDocumentPicker: $showingDocumentPicker
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onAppear {
            if chat.messages.isEmpty {
                chat.setMessages([
                    ChatMessage(
                        role: .assistant,
                        content: "Hello! I can analyze images and files you send me. Try uploading an image or document!"
                    )
                ])
            }
        }
    }
}

struct MessageWithAttachmentsView: View {
    let message: ChatMessage
    let chat: AIChat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageBubbleView(message: message)
            
            // Show attachments for this message
            let attachments = chat.attachments(for: message)
            if !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                        AttachmentView(attachment: attachment)
                    }
                }
                .padding(.leading, message.role == .user ? 60 : 0)
                .padding(.trailing, message.role == .assistant ? 60 : 0)
            }
        }
    }
}

struct AttachmentView: View {
    let attachment: ChatAttachment
    
    var body: some View {
        switch attachment {
        case .image(let imageContent):
            if let data = imageContent.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
        case .file(let fileContent):
            HStack {
                Image(systemName: "doc")
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(fileContent.filename ?? "File")
                        .font(.caption)
                    Text(fileContent.mimeType)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(fileContent.data?.count ?? 0) bytes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
        case .data(let data, let mimeType, let filename):
            HStack {
                Image(systemName: "doc.circle")
                    .foregroundColor(.purple)
                VStack(alignment: .leading) {
                    Text(filename ?? "Data")
                        .font(.caption)
                    Text(mimeType)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(data.count) bytes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct AttachmentInputView: View {
    @ObservedObject var chat: AIChat
    @Binding var selectedImage: UIImage?
    @Binding var showingImagePicker: Bool
    @Binding var showingDocumentPicker: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment buttons
            HStack {
                Button(action: {
                    showingImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo")
                        Text("Image")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(16)
                }
                
                Button(action: {
                    // Simulate adding a document
                    selectedImage = nil
                    // In a real app, you'd use a document picker
                }) {
                    HStack {
                        Image(systemName: "doc")
                        Text("Document")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(16)
                }
                
                Spacer()
                
                if selectedImage != nil {
                    Text("1 attachment")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Text input
            HStack(spacing: 12) {
                TextField("Type a message...", text: $chat.input)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(chat.status != .ready)
                    .focused($isFocused)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button("Send") {
                    sendMessage()
                }
                .disabled((chat.input.isEmpty && selectedImage == nil) || chat.status != .ready)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private func sendMessage() {
        Task {
            var attachments: [ChatAttachment] = []
            
            // Add image attachment if selected
            if let image = selectedImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                attachments.append(.image(ImageContent(data: imageData, mimeType: "image/jpeg")))
            }
            
            if !attachments.isEmpty {
                await chat.sendMessage(withAttachments: attachments)
            } else {
                await chat.sendMessage()
            }
            
            // Clear selected image
            selectedImage = nil
            isFocused = true
        }
    }
}

// Image Picker for iOS
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

#Preview {
    NavigationView {
        AttachmentChatDemoView()
    }
}