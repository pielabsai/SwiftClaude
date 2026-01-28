import SwiftUI

enum ClaudeState: String, Codable {
    case idle
    case thinking
    case toolUse
    case responding
    case waitingForInput
    case error

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .toolUse: return "Tool Use"
        case .responding: return "Responding"
        case .waitingForInput: return "Waiting for Input"
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
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
