import Foundation
import SwiftUI

@Observable
@MainActor
final class SessionManager {
    private static let sessionsKey = "savedSessions"
    private static let selectedSessionKey = "selectedSessionID"

    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    var showingDirectoryPicker = false
    private var statusFileWatcher: StatusFileWatcher?
    private var transcriptWatcher: TranscriptWatcher?
    private var watchedTranscripts: Set<UUID> = []

    var selectedSession: TerminalSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    init() {
        load()
        print("[SC] SessionManager init: \(sessions.count) sessions")
        for session in sessions {
            print("[SC]   - '\(session.name)' id=\(session.id.uuidString.prefix(8))... dir=\(session.directory.path)")
        }
        updateSessionMapping()
        setupTranscriptWatcher()
        setupStatusFileWatcher()
        resumeTranscriptWatching()
    }

    private func resumeTranscriptWatching() {
        // For sessions that have a status with transcript path, start watching
        for session in sessions {
            if let transcriptPath = session.status?.transcriptPath {
                watchedTranscripts.insert(session.id)
                transcriptWatcher?.watchTranscript(for: session.id.uuidString, at: transcriptPath)
            }
        }
    }

    private func setupStatusFileWatcher() {
        statusFileWatcher = StatusFileWatcher()
        statusFileWatcher?.startWatching { [weak self] sessionId, status in
            self?.handleStatusUpdate(sessionId: sessionId, status: status)
        }
    }

    private func setupTranscriptWatcher() {
        transcriptWatcher = TranscriptWatcher()
        transcriptWatcher?.startWatching { [weak self] sessionId, state, debugInfo in
            self?.handleStateUpdate(sessionId: sessionId, state: state, debugInfo: debugInfo)
        }
    }

    private func handleStateUpdate(sessionId: String, state: ClaudeState, debugInfo: StateDebugInfo) {
        print("[SC] State update for \(sessionId.prefix(8))... -> \(state)")

        // Direct match by SwiftClaude session ID
        guard let uuid = UUID(uuidString: sessionId),
              let session = sessions.first(where: { $0.id == uuid }) else {
            print("[SC] State update: no session found for \(sessionId.prefix(8))...")
            return
        }

        print("[SC] Updating state for '\(session.name)' to \(state)")
        session.currentState = state
        session.rawHookStateJSON = debugInfo.hookStateJSON
        session.relevantTranscriptLine = debugInfo.transcriptLine
    }

    private func handleStatusUpdate(sessionId: String, status: ClaudeStatus) {
        // sessionId is Claude's internal ID (from status filename)
        // Look up SwiftClaude session ID from mapping file written by SessionStart hook
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let mappingFile = homeDir.appendingPathComponent(".claude/swiftclaude-status/\(sessionId).mapping")

        guard let swiftClaudeIdString = try? String(contentsOf: mappingFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let swiftClaudeId = UUID(uuidString: swiftClaudeIdString),
              let session = sessions.first(where: { $0.id == swiftClaudeId }) else {
            // No mapping file or no matching session - not a SwiftClaude-managed session
            return
        }

        print("[SC] Status update for '\(session.name)' (claude: \(sessionId.prefix(8))...)")
        updateSessionStatus(session, with: status)
    }

    private func updateSessionStatus(_ session: TerminalSession, with status: ClaudeStatus) {
        session.status = status

        // Start watching transcript if we have a path
        // The watcher handles deduplication - won't re-watch if already watching successfully
        if let transcriptPath = status.transcriptPath {
            transcriptWatcher?.watchTranscript(for: session.id.uuidString, at: transcriptPath)
        }
    }

    func createSession(at directory: URL) {
        let session = TerminalSession(directory: directory)
        sessions.append(session)
        selectedSessionID = session.id
        save()
        updateSessionMapping()
    }

    private func updateSessionMapping() {
        // Write directory -> session ID mapping for the statusline hook
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let mappingFile = homeDir.appendingPathComponent(".claude/swiftclaude-sessions.json")

        var mapping: [String: String] = [:]
        for session in sessions {
            mapping[session.directory.path] = session.id.uuidString
        }

        if let data = try? JSONEncoder().encode(mapping) {
            try? data.write(to: mappingFile)
            print("[SC] Updated session mapping: \(mapping)")
        }
    }

    func deleteSession(_ session: TerminalSession) {
        // Clean up watchers
        let sessionIdString = session.id.uuidString
        statusFileWatcher?.cleanupStatusFile(for: sessionIdString)
        transcriptWatcher?.stopWatching(sessionId: sessionIdString)
        watchedTranscripts.remove(session.id)

        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
        save()
        updateSessionMapping()
    }

    func requestNewSession() {
        showingDirectoryPicker = true
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: Self.sessionsKey)
        }
        if let selectedID = selectedSessionID {
            UserDefaults.standard.set(selectedID.uuidString, forKey: Self.selectedSessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedSessionKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
           let decoded = try? JSONDecoder().decode([TerminalSession].self, from: data) {
            sessions = decoded
        }
        if let idString = UserDefaults.standard.string(forKey: Self.selectedSessionKey),
           let uuid = UUID(uuidString: idString),
           sessions.contains(where: { $0.id == uuid }) {
            selectedSessionID = uuid
        } else {
            selectedSessionID = sessions.first?.id
        }
    }
}
