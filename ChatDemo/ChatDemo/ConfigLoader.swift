//
//  ConfigLoader.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import Foundation

struct ConfigLoader {
    private static func loadValue(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String,
              value.isEmpty == false else {
            return nil
        }
        return value
    }
    
    static func loadAPIKey() -> String? {
        loadValue(for: "OPENAI_API_KEY")
    }
    
    static func loadAnthropicAPIKey() -> String? {
        loadValue(for: "ANTHROPIC_API_KEY")
    }
    
    static func loadOpenRouterAPIKey() -> String? {
        loadValue(for: "OPENROUTER_API_KEY")
    }
}
