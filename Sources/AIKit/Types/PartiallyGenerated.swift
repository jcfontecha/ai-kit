import Foundation

// MARK: - Partially Generated Type for Streaming

/// Represents a partially generated object during streaming.
/// 
/// This type provides access to incomplete objects as they're being generated,
/// allowing for progressive UI updates and real-time feedback.
public struct PartiallyGenerated<T: SchemaProviding> {
    /// The partial object with all properties as optionals
    public let object: T.Partial
    
    /// Raw JSON snapshot of the current state
    public let snapshot: String
    
    /// Generation progress information
    public let progress: Progress
    
    /// Whether all required fields have been generated
    public let isComplete: Bool
    
    /// Progress tracking for partial generation
    public struct Progress {
        /// Number of fields that have been completed
        public let completedFields: Int
        
        /// Total number of fields in the schema
        public let totalFields: Int
        
        /// Percentage of completion (0.0 to 1.0)
        public let percentage: Double
        
        /// Status of each field
        public let fieldStatus: [String: FieldStatus]
        
        /// Human-readable description of progress
        public var description: String {
            "\(completedFields)/\(totalFields) fields (\(Int(percentage * 100))%)"
        }
    }
}

// MARK: - Error for Incomplete Objects

/// Error thrown when trying to complete a partial object that's missing required fields
public struct IncompleteObjectError: Error, LocalizedError {
    public let missingFields: [String]
    public let presentFields: [String]
    
    public var errorDescription: String? {
        "Cannot complete object: missing required fields: \(missingFields.joined(separator: ", "))"
    }
}