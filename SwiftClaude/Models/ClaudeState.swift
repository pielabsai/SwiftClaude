import SwiftUI

enum ClaudeState: String, Codable {
    case idle
    case thinking
    case toolUse
    case responding
    case waitingForInput
    case askingQuestion
    case error

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .toolUse: return "Tool Use"
        case .responding: return "Responding"
        case .waitingForInput: return "Waiting for Input"
        case .askingQuestion: return "Asking Question"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .thinking: return .purple
        case .toolUse: return .blue
        case .responding: return .green
        case .waitingForInput: return .orange
        case .askingQuestion: return .yellow
        case .error: return .red
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "terminal"
        case .thinking: return "brain"
        case .toolUse: return "hammer.fill"
        case .responding: return "text.bubble.fill"
        case .waitingForInput: return "keyboard"
        case .askingQuestion: return "questionmark.bubble.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
