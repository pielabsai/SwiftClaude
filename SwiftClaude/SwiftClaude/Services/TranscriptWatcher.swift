import Foundation

@MainActor
final class TranscriptWatcher {
    private var fileMonitors: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private(set) var transcriptPaths: [String: String] = [:]
    private var onStateUpdate: ((String, ClaudeState) -> Void)?

    // Directory watchers for pending transcript files
    private var pendingWatches: [String: String] = [:]  // sessionId -> path
    private var directoryWatchers: [String: DispatchSourceFileSystemObject] = [:]  // directory -> watcher
    private var directoryFDs: [String: Int32] = [:]

    func startWatching(onStateUpdate: @escaping (String, ClaudeState) -> Void) {
        self.onStateUpdate = onStateUpdate
    }

    func watchTranscript(for sessionId: String, at path: String) {
        // If already watching this exact path, skip
        if fileMonitors[sessionId] != nil && transcriptPaths[sessionId] == path {
            return
        }

        // If watching a different path, stop the old watcher first
        if fileMonitors[sessionId] != nil && transcriptPaths[sessionId] != path {
            print("[SC] Transcript path changed, switching to new file")
            stopWatching(sessionId: sessionId)
        }

        transcriptPaths[sessionId] = path

        // Try to open the file
        let fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor >= 0 {
            // File exists - start watching it
            startFileWatch(sessionId: sessionId, path: path, fd: fileDescriptor)
        } else {
            // File doesn't exist yet - watch the directory for it to appear
            print("[SC] Transcript not ready, watching directory for \(sessionId.prefix(8))...")
            watchDirectoryForFile(sessionId: sessionId, path: path)
        }
    }

    private func startFileWatch(sessionId: String, path: String, fd: Int32) {
        // Remove from pending if it was there
        pendingWatches.removeValue(forKey: sessionId)

        print("[SC] Opened transcript fd=\(fd) for \(sessionId.prefix(8))...")
        fileDescriptors[sessionId] = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkTranscript(sessionId: sessionId)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        fileMonitors[sessionId] = source
        source.resume()

        // Initial check
        checkTranscript(sessionId: sessionId)
    }

    private func watchDirectoryForFile(sessionId: String, path: String) {
        pendingWatches[sessionId] = path

        let directory = (path as NSString).deletingLastPathComponent

        // If already watching this directory, we're done
        if directoryWatchers[directory] != nil {
            return
        }

        // Open directory for monitoring
        let dirFD = open(directory, O_EVTONLY)
        guard dirFD >= 0 else {
            print("[SC] Failed to open directory for watching: \(directory)")
            return
        }

        directoryFDs[directory] = dirFD

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkPendingFiles()
            }
        }

        source.setCancelHandler {
            close(dirFD)
        }

        directoryWatchers[directory] = source
        source.resume()
    }

    private func checkPendingFiles() {
        for (sessionId, path) in pendingWatches {
            let fd = open(path, O_EVTONLY)
            if fd >= 0 {
                print("[SC] Pending transcript now available for \(sessionId.prefix(8))...")
                startFileWatch(sessionId: sessionId, path: path, fd: fd)
            }
        }

        // Clean up directory watchers if no more pending files need them
        cleanupDirectoryWatchers()
    }

    private func cleanupDirectoryWatchers() {
        let neededDirectories = Set(pendingWatches.values.map { ($0 as NSString).deletingLastPathComponent })

        for directory in Array(directoryWatchers.keys) {
            if !neededDirectories.contains(directory) {
                directoryWatchers[directory]?.cancel()
                directoryWatchers.removeValue(forKey: directory)
                directoryFDs.removeValue(forKey: directory)
            }
        }
    }

    func stopWatching(sessionId: String) {
        fileMonitors[sessionId]?.cancel()
        fileMonitors.removeValue(forKey: sessionId)
        fileDescriptors.removeValue(forKey: sessionId)
        transcriptPaths.removeValue(forKey: sessionId)
        pendingWatches.removeValue(forKey: sessionId)
        cleanupDirectoryWatchers()
    }

    func stopAll() {
        for sessionId in Array(fileMonitors.keys) {
            stopWatching(sessionId: sessionId)
        }
        pendingWatches.removeAll()
        for (_, watcher) in directoryWatchers {
            watcher.cancel()
        }
        directoryWatchers.removeAll()
        directoryFDs.removeAll()
    }

    private func checkTranscript(sessionId: String) {
        guard let path = transcriptPaths[sessionId] else { return }

        // Read the file using FileManager (separate from the monitoring file descriptor)
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        // Get lines in reverse order, find the last relevant entry
        let lines = content.components(separatedBy: .newlines).reversed()
        var checkedCount = 0
        for line in lines where !line.isEmpty {
            guard let entry = parseTranscriptEntry(line) else { continue }

            let entryType = entry.type ?? ""
            checkedCount += 1

            // "summary" means Claude finished the turn
            if entryType == "summary" {
                print("[SC] State: waitingForInput (summary found at position \(checkedCount))")
                onStateUpdate?(sessionId, .waitingForInput)
                return
            }

            // Skip other non-message entries
            if entryType == "file-history-snapshot" {
                continue
            }

            // Found a relevant entry
            let state = determineState(from: entry)
            let stopInfo = entry.stopReason ?? entry.message?.stopReason ?? "none"
            print("[SC] State: \(state) (from \(entryType) at position \(checkedCount), stop_reason: \(stopInfo))")
            onStateUpdate?(sessionId, state)
            return
        }
    }

    private func parseTranscriptEntry(_ line: String) -> TranscriptEntry? {
        guard let data = line.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(TranscriptEntry.self, from: data)
        } catch {
            print("[SC] Parse error: \(error)")
            return nil
        }
    }

    private func determineState(from entry: TranscriptEntry) -> ClaudeState {
        // Check if this is a user message - means we submitted and Claude should be thinking
        if entry.type == "user" {
            return .thinking
        }

        // Check for stop_reason at entry level (Claude Code format)
        // stop_reason can be at entry level or message level
        let entryStopReason = entry.stopReason ?? entry.message?.stopReason

        // If there's a stop_reason at entry level, Claude has finished this turn
        // Valid stop reasons: end_turn, stop_sequence, max_tokens (not tool_use which means continuation)
        if let stopReason = entryStopReason, stopReason != "tool_use" {
            return .waitingForInput
        }

        // Check the message content
        guard let message = entry.message else {
            print("[SC] No message in entry, type=\(entry.type ?? "nil")")
            return .idle
        }

        // Check content types in the message
        if let content = message.content, let firstContent = content.first {
            switch firstContent.type {
            case "thinking":
                return .thinking
            case "tool_use":
                return .toolUse
            case "tool_result":
                return .thinking  // After tool result, Claude will continue thinking
            case "text":
                // Text entry is written only when response is complete
                // (Claude Code doesn't stream partial text to transcript)
                return .waitingForInput
            default:
                print("[SC] Unknown content type: \(firstContent.type)")
                break
            }
        } else {
            print("[SC] No content in message, stopReason=\(entryStopReason ?? "nil")")
        }

        return .idle
    }
}

// MARK: - Transcript Entry Models

struct TranscriptEntry: Decodable {
    let sessionId: String?
    let type: String?
    let message: TranscriptMessage?
    let stopReason: String?  // stop_reason can be at entry level or message level

    enum CodingKeys: String, CodingKey {
        case sessionId
        case type
        case message
        case stopReason = "stop_reason"
    }
}

struct TranscriptMessage: Decodable {
    let role: String?
    let contentArray: [TranscriptContent]?
    let contentString: String?
    let stopReason: String?

    var content: [TranscriptContent]? { contentArray }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case stopReason = "stop_reason"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)

        // content can be either a string or an array
        if let array = try? container.decodeIfPresent([TranscriptContent].self, forKey: .content) {
            contentArray = array
            contentString = nil
        } else if let string = try? container.decodeIfPresent(String.self, forKey: .content) {
            contentString = string
            contentArray = nil
        } else {
            contentArray = nil
            contentString = nil
        }
    }
}

struct TranscriptContent: Codable {
    let type: String
}
