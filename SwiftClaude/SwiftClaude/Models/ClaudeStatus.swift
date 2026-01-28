import Foundation

struct ClaudeStatus: Codable, Equatable {
    let sessionId: String
    let transcriptPath: String?
    let model: ModelInfo?
    let contextWindow: ContextWindow?
    let cost: CostInfo?
    let workspace: WorkspaceInfo?
    var rawJSON: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case model
        case contextWindow = "context_window"
        case cost
        case workspace
    }

    struct ModelInfo: Codable, Equatable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct ContextWindow: Codable, Equatable {
        let usedPercentage: Double?
        let remainingPercentage: Double?
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        let contextWindowSize: Int?

        // Computed for display
        var usedTokens: Int? {
            guard let input = totalInputTokens, let output = totalOutputTokens else { return nil }
            return input + output
        }

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case remainingPercentage = "remaining_percentage"
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case contextWindowSize = "context_window_size"
        }
    }

    struct CostInfo: Codable, Equatable {
        let totalCostUsd: Double?
        let durationMs: Int?
        let durationApiMs: Int?
        let linesAdded: Int?
        let linesRemoved: Int?
        let messageCount: Int?
        let turnCount: Int?

        enum CodingKeys: String, CodingKey {
            case totalCostUsd = "total_cost_usd"
            case durationMs = "duration_ms"
            case durationApiMs = "duration_api_ms"
            case linesAdded = "lines_added"
            case linesRemoved = "lines_removed"
            case messageCount = "message_count"
            case turnCount = "turn_count"
        }
    }

    struct WorkspaceInfo: Codable, Equatable {
        let currentDir: String?
        let projectDir: String?

        enum CodingKeys: String, CodingKey {
            case currentDir = "current_dir"
            case projectDir = "project_dir"
        }
    }
}

extension ClaudeStatus {
    static func parse(from jsonString: String) -> ClaudeStatus? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            var status = try JSONDecoder().decode(ClaudeStatus.self, from: data)
            status.rawJSON = jsonString
            return status
        } catch {
            print("Failed to parse ClaudeStatus: \(error)")
            return nil
        }
    }

    static func parse(from url: URL) -> ClaudeStatus? {
        do {
            let jsonString = try String(contentsOf: url, encoding: .utf8)
            return parse(from: jsonString)
        } catch {
            print("Failed to read status file: \(error)")
            return nil
        }
    }
}
