import Foundation

@MainActor
final class StatusFileWatcher {
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let statusDirectory: URL
    private var onStatusUpdate: ((String, ClaudeStatus) -> Void)?
    private var lastModificationDates: [String: Date] = [:]

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        statusDirectory = homeDir.appendingPathComponent(".claude/swiftclaude-status")
    }

    func startWatching(onStatusUpdate: @escaping (String, ClaudeStatus) -> Void) {
        self.onStatusUpdate = onStatusUpdate

        // Ensure status directory exists
        try? FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)

        // Open directory for monitoring
        fileDescriptor = open(statusDirectory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("StatusFileWatcher: Failed to open status directory")
            return
        }

        // Create dispatch source
        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        directorySource?.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }

        directorySource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        directorySource?.resume()

        // Initial check
        checkForUpdates()
    }

    func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }

    private func checkForUpdates() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: statusDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }

        for fileURL in jsonFiles {
            let sessionId = fileURL.deletingPathExtension().lastPathComponent

            // Check if file was modified
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let modDate = attributes[.modificationDate] as? Date else {
                continue
            }

            if let lastMod = lastModificationDates[sessionId], lastMod >= modDate {
                continue
            }

            lastModificationDates[sessionId] = modDate

            // Parse and notify
            if let status = ClaudeStatus.parse(from: fileURL) {
                onStatusUpdate?(sessionId, status)
            }
        }
    }

    func cleanupStatusFile(for sessionId: String) {
        let fileURL = statusDirectory.appendingPathComponent("\(sessionId).json")
        try? FileManager.default.removeItem(at: fileURL)
        lastModificationDates.removeValue(forKey: sessionId)
    }

    deinit {
        directorySource?.cancel()
    }
}
