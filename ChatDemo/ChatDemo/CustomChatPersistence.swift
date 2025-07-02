//
//  CustomChatPersistence.swift
//  ChatDemo
//
//  Demonstrates custom persistence implementations using the ChatPersistence protocol
//

import Foundation
import AIKit

// MARK: - CloudKit-style Persistence (Example)

/// Example of a cloud-based persistence implementation
/// This simulates saving to a cloud service with sync capabilities
class CloudChatPersistence: ChatPersistence {
    private let syncDelay: TimeInterval
    private var cloudStorage: [String: Data] = [:]
    
    init(syncDelay: TimeInterval = 0.5) {
        self.syncDelay = syncDelay
    }
    
    func save(_ messages: [ChatMessage], for chatId: String) async throws {
        // Simulate cloud sync delay
        try await Task.sleep(nanoseconds: UInt64(syncDelay * 1_000_000_000))
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(messages)
        
        // Simulate cloud storage
        cloudStorage[chatId] = data
        
        print("☁️ Saved \(messages.count) messages to cloud for chat: \(chatId)")
    }
    
    func load(for chatId: String) async throws -> [ChatMessage] {
        // Simulate cloud sync delay
        try await Task.sleep(nanoseconds: UInt64(syncDelay * 1_000_000_000))
        
        guard let data = cloudStorage[chatId] else {
            print("☁️ No cloud data found for chat: \(chatId)")
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let messages = try decoder.decode([ChatMessage].self, from: data)
        
        print("☁️ Loaded \(messages.count) messages from cloud for chat: \(chatId)")
        return messages
    }
    
    func delete(for chatId: String) async throws {
        cloudStorage.removeValue(forKey: chatId)
        print("☁️ Deleted cloud data for chat: \(chatId)")
    }
}

// MARK: - Encrypted Persistence

/// Example of an encrypted persistence implementation
/// Encrypts chat messages before saving (simulation - not real encryption)
struct EncryptedChatPersistence: ChatPersistence {
    private let baseDirectory: URL
    private let encryptionKey: String
    
    init(encryptionKey: String = "demo-key") throws {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        
        self.baseDirectory = documentsPath.appendingPathComponent("EncryptedChats", isDirectory: true)
        self.encryptionKey = encryptionKey
        
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    func save(_ messages: [ChatMessage], for chatId: String) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(messages)
        
        // Simulate encryption (just base64 for demo)
        let encrypted = data.base64EncodedData()
        
        let fileURL = baseDirectory.appendingPathComponent("\(chatId).encrypted")
        try encrypted.write(to: fileURL)
        
        print("🔐 Saved encrypted chat: \(chatId) (\(messages.count) messages)")
    }
    
    func load(for chatId: String) async throws -> [ChatMessage] {
        let fileURL = baseDirectory.appendingPathComponent("\(chatId).encrypted")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("🔐 No encrypted file found for chat: \(chatId)")
            return []
        }
        
        let encryptedData = try Data(contentsOf: fileURL)
        
        // Simulate decryption (just base64 for demo)
        guard let decryptedData = Data(base64Encoded: encryptedData) else {
            throw ChatPersistenceError.decryptionFailed
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let messages = try decoder.decode([ChatMessage].self, from: decryptedData)
        
        print("🔐 Loaded encrypted chat: \(chatId) (\(messages.count) messages)")
        return messages
    }
    
    func delete(for chatId: String) async throws {
        let fileURL = baseDirectory.appendingPathComponent("\(chatId).encrypted")
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            print("🔐 Deleted encrypted chat: \(chatId)")
        }
    }
}

// MARK: - Version-Aware Persistence

/// Example of persistence with versioning and migration support
actor VersionedChatPersistence: ChatPersistence {
    private struct VersionedData: Codable {
        let version: Int
        let messages: [ChatMessage]
        let metadata: [String: String]
    }
    
    private let currentVersion = 2
    private var storage: [String: VersionedData] = [:]
    
    func save(_ messages: [ChatMessage], for chatId: String) async throws {
        let versionedData = VersionedData(
            version: currentVersion,
            messages: messages,
            metadata: [
                "savedAt": ISO8601DateFormatter().string(from: Date()),
                "messageCount": "\(messages.count)"
            ]
        )
        
        storage[chatId] = versionedData
        print("📦 Saved versioned chat (v\(currentVersion)): \(chatId)")
    }
    
    func load(for chatId: String) async throws -> [ChatMessage] {
        guard let versionedData = storage[chatId] else {
            print("📦 No versioned data found for chat: \(chatId)")
            return []
        }
        
        // Handle version migration if needed
        if versionedData.version < currentVersion {
            print("📦 Migrating chat from v\(versionedData.version) to v\(currentVersion)")
            // In a real app, you'd perform migration here
        }
        
        print("📦 Loaded versioned chat (v\(versionedData.version)): \(chatId)")
        return versionedData.messages
    }
    
    func delete(for chatId: String) async throws {
        storage.removeValue(forKey: chatId)
        print("📦 Deleted versioned chat: \(chatId)")
    }
}

// MARK: - Composite Persistence

/// Example of combining multiple persistence strategies
/// Saves to both local and cloud storage for redundancy
class CompositeChatPersistence: ChatPersistence {
    private let localPersistence: ChatPersistence
    private let remotePersistence: ChatPersistence
    
    init(local: ChatPersistence, remote: ChatPersistence) {
        self.localPersistence = local
        self.remotePersistence = remote
    }
    
    func save(_ messages: [ChatMessage], for chatId: String) async throws {
        // Save to both local and remote
        async let localSave: () = localPersistence.save(messages, for: chatId)
        async let remoteSave: () = remotePersistence.save(messages, for: chatId)
        
        try await localSave
        try await remoteSave
        
        print("💾 Saved to both local and remote storage")
    }
    
    func load(for chatId: String) async throws -> [ChatMessage] {
        // Try local first, fall back to remote
        do {
            let localMessages = try await localPersistence.load(for: chatId)
            if !localMessages.isEmpty {
                print("💾 Loaded from local storage")
                return localMessages
            }
        } catch {
            print("💾 Local load failed, trying remote...")
        }
        
        let remoteMessages = try await remotePersistence.load(for: chatId)
        print("💾 Loaded from remote storage")
        
        // Cache locally for next time
        if !remoteMessages.isEmpty {
            try? await localPersistence.save(remoteMessages, for: chatId)
        }
        
        return remoteMessages
    }
    
    func delete(for chatId: String) async throws {
        async let localDelete: () = localPersistence.delete(for: chatId)
        async let remoteDelete: () = remotePersistence.delete(for: chatId)
        
        try await localDelete
        try await remoteDelete
        
        print("💾 Deleted from both local and remote storage")
    }
}

// MARK: - Error Types

enum ChatPersistenceError: LocalizedError {
    case decryptionFailed
    case versionMismatch
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .decryptionFailed:
            return "Failed to decrypt chat data"
        case .versionMismatch:
            return "Chat data version is incompatible"
        case .syncFailed:
            return "Failed to sync with cloud storage"
        }
    }
}