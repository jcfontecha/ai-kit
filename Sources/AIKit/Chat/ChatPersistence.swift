import Foundation

/// Protocol for persisting chat messages
///
/// Implement this protocol to provide custom storage for chat messages.
/// The framework doesn't make assumptions about where or how you store data.
///
/// ## Example Implementation
/// ```swift
/// class CloudChatPersistence: ChatPersistence {
///     func save(_ messages: [ChatMessage], for chatId: String) async throws {
///         // Save to cloud storage
///         try await cloudService.save(messages, key: chatId)
///     }
///     
///     func load(for chatId: String) async throws -> [ChatMessage] {
///         // Load from cloud storage
///         return try await cloudService.load(key: chatId)
///     }
/// }
/// ```
@available(iOS 16.0, macOS 13.0, *)
public protocol ChatPersistence: Sendable {
    /// Save chat messages
    /// - Parameters:
    ///   - messages: The messages to save
    ///   - chatId: A unique identifier for this chat session
    func save(_ messages: [ChatMessage], for chatId: String) async throws
    
    /// Load chat messages
    /// - Parameter chatId: The unique identifier for the chat session
    /// - Returns: The loaded messages, or empty array if none exist
    func load(for chatId: String) async throws -> [ChatMessage]
    
    /// Delete saved chat messages
    /// - Parameter chatId: The unique identifier for the chat session
    func delete(for chatId: String) async throws
}

// MARK: - Memory Persistence (for testing)

/// An in-memory implementation of ChatPersistence, useful for testing
@available(iOS 16.0, macOS 13.0, *)
public actor MemoryChatPersistence: ChatPersistence {
    private var storage: [String: [ChatMessage]] = [:]
    
    public init() {}
    
    public func save(_ messages: [ChatMessage], for chatId: String) async throws {
        storage[chatId] = messages
    }
    
    public func load(for chatId: String) async throws -> [ChatMessage] {
        return storage[chatId] ?? []
    }
    
    public func delete(for chatId: String) async throws {
        storage.removeValue(forKey: chatId)
    }
}

// MARK: - UserDefaults Persistence (backward compatibility)

/// UserDefaults implementation of ChatPersistence
///
/// Note: UserDefaults has size limitations and synchronous I/O.
/// Consider using FileChatPersistence or a custom implementation for production apps.
@available(iOS 16.0, macOS 13.0, *)
public struct UserDefaultsChatPersistence: ChatPersistence {
    private let keyPrefix: String
    
    public init(keyPrefix: String = "AIChat.") {
        self.keyPrefix = keyPrefix
    }
    
    public func save(_ messages: [ChatMessage], for chatId: String) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(messages)
        UserDefaults.standard.set(data, forKey: keyPrefix + chatId)
    }
    
    public func load(for chatId: String) async throws -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + chatId) else {
            return []
        }
        let decoder = JSONDecoder()
        return try decoder.decode([ChatMessage].self, from: data)
    }
    
    public func delete(for chatId: String) async throws {
        UserDefaults.standard.removeObject(forKey: keyPrefix + chatId)
    }
}

// MARK: - File-based Persistence

/// File-based implementation of ChatPersistence
///
/// Stores chat messages as JSON files in a specified directory.
/// More suitable for larger chat histories than UserDefaults.
@available(iOS 16.0, macOS 13.0, *)
public struct FileChatPersistence: ChatPersistence {
    private let directory: URL
    
    /// Initialize with a directory URL
    /// - Parameter directory: The directory to store chat files. Will be created if it doesn't exist.
    public init(directory: URL) throws {
        self.directory = directory
        
        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    /// Initialize with a default directory in the app's documents folder
    public init() throws {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        
        self.directory = documentsPath.appendingPathComponent("AIChats", isDirectory: true)
        
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    private func fileURL(for chatId: String) -> URL {
        // Sanitize chatId to be filesystem-safe
        let sanitized = chatId.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        
        return directory.appendingPathComponent("\(sanitized).json")
    }
    
    public func save(_ messages: [ChatMessage], for chatId: String) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(messages)
        try data.write(to: fileURL(for: chatId))
    }
    
    public func load(for chatId: String) async throws -> [ChatMessage] {
        let url = fileURL(for: chatId)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([ChatMessage].self, from: data)
    }
    
    public func delete(for chatId: String) async throws {
        let url = fileURL(for: chatId)
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}