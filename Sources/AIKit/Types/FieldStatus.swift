import Foundation

// MARK: - Field Status for Partial Types

/// Status of a field during partial generation
public enum FieldStatus {
    case notStarted
    case inProgress
    case completed
    
    public var symbol: String {
        switch self {
        case .notStarted: return "⏳"
        case .inProgress: return "⚡"
        case .completed: return "✅"
        }
    }
}