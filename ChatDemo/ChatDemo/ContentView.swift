//
//  ContentView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                Section("AIChat Demo Features") {
                    NavigationLink("Basic Chat", destination: BasicChatDemoView())
                    NavigationLink("Chat with Tools", destination: ToolChatDemoView())
                    NavigationLink("File Attachments", destination: AttachmentChatDemoView())
                    NavigationLink("Persistent Chat", destination: PersistentChatDemoView())
                    NavigationLink("Advanced Persistence", destination: AdvancedPersistentChatDemoView())
                    NavigationLink("Custom Styled Chat", destination: CustomStyledChatView())
                }
                
                Section("Advanced Features") {
                    NavigationLink("Message Management", destination: MessageManagementDemoView())
                    NavigationLink("Error Handling", destination: ErrorHandlingDemoView())
                    NavigationLink("Streaming Control", destination: StreamingControlDemoView())
                }
            }
            .navigationTitle("AIChat Demos")
        }
    }
}

#Preview {
    ContentView()
}
