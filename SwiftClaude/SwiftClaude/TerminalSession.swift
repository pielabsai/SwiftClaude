import Foundation
import SwiftTerm

@Observable
final class TerminalSession: Identifiable, Codable {
    let id: UUID
    let directory: URL
    var name: String
    var terminalView: LocalProcessTerminalView?
    var status: ClaudeStatus?
    var currentState: ClaudeState = .idle

    // Debug info
    var rawHookStateJSON: String?
    var relevantTranscriptLine: String?

    enum CodingKeys: String, CodingKey {
        case id, directory, name
    }

    init(directory: URL) {
        self.id = UUID()
        self.directory = directory
        self.name = directory.lastPathComponent
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        directory = try container.decode(URL.self, forKey: .directory)
        name = try container.decode(String.self, forKey: .name)
        terminalView = nil
        status = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(directory, forKey: .directory)
        try container.encode(name, forKey: .name)
    }
}
