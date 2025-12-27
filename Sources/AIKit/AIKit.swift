@_exported import AIKitProviders

import AIKitCore

// MARK: - Curated re-exports (keep app surface small)

public typealias AIClient = AIKitCore.AIClient

/// Canonical JSON value type used across AIKit APIs.
///
/// Use `AIKit.JSONValue` to disambiguate with app-level `JSONValue` types.
public typealias JSONValue = AIKitProviders.JSONValue

// ChatStore surface types
public typealias ChatMessage = AIKitCore.ChatMessage
public typealias ChatMessagePart = AIKitCore.ChatMessagePart
public typealias ChatToolPart = AIKitCore.ChatToolPart
public typealias ChatRequestOptions = AIKitCore.ChatRequestOptions
public typealias ChatSessionStatus = AIKitCore.ChatSessionStatus
public typealias ChatSessionSnapshot = AIKitCore.ChatSessionSnapshot

// Common configuration types used by ChatStore/AIClient
public typealias SystemPrompt = AIKitCore.SystemPrompt
public typealias ToolRegistry = AIKitCore.ToolRegistry
public typealias ToolChoice = AIKitProviders.ToolChoice
