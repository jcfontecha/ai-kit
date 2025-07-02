//
//  ConfigLoader.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import Foundation

struct ConfigLoader {
    static func loadAPIKey() -> String? {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let apiKey = plist["OPENAI_API_KEY"] as? String else {
            return nil
        }
        return apiKey
    }
}