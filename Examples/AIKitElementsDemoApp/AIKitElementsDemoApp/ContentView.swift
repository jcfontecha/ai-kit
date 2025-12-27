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
                ForEach(ComponentCategory.allCases) { category in
                    let components = ComponentCatalog.components(in: category, matching: query)
                    if components.isEmpty {
                        EmptyView()
                    } else {
                        Section(category.title) {
                            ForEach(components) { component in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.name)
                                    Text(component.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(component.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AIKit Elements")
            .searchable(text: $query, placement: .sidebar, prompt: "Search components")
        } detail: {
            if let selection, let component = ComponentCatalog.component(id: selection) {
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
