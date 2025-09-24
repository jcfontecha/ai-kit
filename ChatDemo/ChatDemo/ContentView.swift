//
//  ContentView.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ContentView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    @State private var isPresentingProviderSheet = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Provider Settings") {
                    Button {
                        isPresentingProviderSheet = true
                    } label: {
                        HStack {
                            Label("Active Provider", systemImage: "bolt.horizontal")
                            Spacer()
                            Text(activeProviderSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if let message = providerStore.availabilityMessage(for: providerStore.selection.provider) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                
                Section("AIChat Demo Features") {
                    NavigationLink("Basic Chat", destination: BasicChatDemoView())
                    NavigationLink("Chat with Tools", destination: ToolChatDemoView())
                    NavigationLink("Inline Tool Rendering", destination: InlineToolChatDemoView())
                    NavigationLink("File Attachments", destination: AttachmentChatDemoView())
                    NavigationLink("Persistent Chat", destination: PersistentChatDemoView())
                    NavigationLink("Advanced Persistence", destination: AdvancedPersistentChatDemoView())
                    NavigationLink("Custom Styled Chat", destination: CustomStyledChatView())
                    if #available(iOS 16.0, macOS 13.0, *) {
                        NavigationLink("OpenRouter Chat", destination: OpenRouterChatDemoView())
                    }
                }
                
                Section("Advanced Features") {
                    NavigationLink("Message Management", destination: MessageManagementDemoView())
                    NavigationLink("Error Handling", destination: ErrorHandlingDemoView())
                    NavigationLink("Streaming Control", destination: StreamingControlDemoView())
                }
            }
            .navigationTitle("AIChat Demos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingProviderSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Select AI provider")
                }
            }
        }
        .sheet(isPresented: $isPresentingProviderSheet) {
            ProviderSelectionView()
                .environmentObject(providerStore)
        }
    }
    
    private var activeProviderSummary: String {
        let fallback = providerStore.entries[providerStore.selection.provider]?.defaultModel ?? "gpt-4o-mini"
        return providerStore.selectionSummary(fallbackModelId: fallback)
    }
}

#Preview {
    if #available(iOS 16.0, macOS 13.0, *) {
        ContentView()
            .environmentObject(ProviderStore())
    } else {
        Text("Requires iOS 16 or macOS 13")
    }
}
