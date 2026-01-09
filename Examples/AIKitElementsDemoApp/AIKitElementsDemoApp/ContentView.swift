//
//  ContentView.swift
//  AIKitElementsDemoApp
//
//  Created by Juan Carlos on 12/26/25.
//

import SwiftUI

struct ContentView: View {
    @State private var query: String = ""
    @State private var selection: ComponentID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Demos") {
                    NavigationLink(value: "demo/chat") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chat Demo")
                            Text("Live OpenRouter chat using the current component set")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink(value: "demo/fresh-chat") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fresh Chat Demo")
                            Text("Live OpenRouter chat (no initial messages)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink(value: "demo/long-chat") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Long Chat Demo")
                            Text("Long conversation with tool calls + images")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink(value: "demo/chat-sheet") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chat Sheet Demo")
                            Text("Chat embedded in a resizable sheet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink(value: "settings/openrouter") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Settings")
                            Text("Configure OpenRouter API key + model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(ComponentCategory.allCases) { category in
                    let components = ComponentCatalog.components(in: category, matching: query)
                    if components.isEmpty {
                        EmptyView()
                    } else {
                        Section(category.title) {
                            ForEach(components) { component in
                                NavigationLink(value: component.id) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(component.name)
                                        Text(component.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("AIKit Elements")
            .searchable(text: $query, placement: .sidebar, prompt: "Search components")
        } detail: {
            if selection == "demo/chat" {
                #if os(iOS)
                SimpleChatDemoView()
                    .navigationTitle("Chat Demo")
                    .navigationBarTitleDisplayMode(.inline)
                #else
                SimpleChatDemoView()
                    .navigationTitle("Chat Demo")
                #endif
            } else if selection == "demo/fresh-chat" {
                #if os(iOS)
                FreshChatDemoView()
                    .navigationTitle("Fresh Chat Demo")
                    .navigationBarTitleDisplayMode(.inline)
                #else
                FreshChatDemoView()
                    .navigationTitle("Fresh Chat Demo")
                #endif
            } else if selection == "demo/long-chat" {
                #if os(iOS)
                LongChatWithImagesDemoView()
                    .navigationTitle("Long Chat Demo")
                    .navigationBarTitleDisplayMode(.inline)
                #else
                LongChatWithImagesDemoView()
                    .navigationTitle("Long Chat Demo")
                #endif
            } else if selection == "demo/chat-sheet" {
                #if os(iOS)
                ChatSheetDemoView()
                    .navigationTitle("Chat Sheet Demo")
                    .navigationBarTitleDisplayMode(.inline)
                #else
                ChatSheetDemoView()
                    .navigationTitle("Chat Sheet Demo")
                #endif
            } else if selection == "settings/openrouter" {
                #if os(iOS)
                OpenRouterSettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                #else
                OpenRouterSettingsView()
                    .navigationTitle("Settings")
                #endif
            } else if let selection, let component = ComponentCatalog.component(id: selection) {
                #if os(iOS)
                ComponentDetailView(component: component)
                    .navigationTitle(component.name)
                    .navigationBarTitleDisplayMode(.inline)
                #else
                ComponentDetailView(component: component)
                    .navigationTitle(component.name)
                #endif
            } else {
                ContentUnavailableView("Select a component", systemImage: "square.grid.2x2")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
