//
//  ChatDemoApp.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import SwiftUI

@main
@available(iOS 16.0, macOS 13.0, *)
struct ChatDemoApp: App {
    @StateObject private var providerStore = ProviderStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(providerStore)
        }
    }
}
