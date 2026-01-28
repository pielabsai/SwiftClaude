import Foundation
import SwiftUI

@Observable
@MainActor
final class SessionManager {
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    var showingDirectoryPicker = false

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    func createSession(at directory: URL) {
        let session = TerminalSession(directory: directory)
        sessions.append(session)
        selectedSessionID = session.id
    }

    func deleteSession(_ session: TerminalSession) {
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
    }

    func requestNewSession() {
        showingDirectoryPicker = true
    }
}
