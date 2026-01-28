import Foundation

final class ClaudeConfigManager {
    static let shared = ClaudeConfigManager()

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser
    private var claudeDir: URL { homeDir.appendingPathComponent(".claude") }
    private var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }
    private var statusLineScript: URL { claudeDir.appendingPathComponent("swiftclaude-statusline.sh") }
    private var statusDir: URL { claudeDir.appendingPathComponent("swiftclaude-status") }

    private init() {}

    func configureOnLaunch() {
        ensureDirectoriesExist()
        writeStatusLineScript()
        updateClaudeSettings()
    }

    private func ensureDirectoriesExist() {
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
    }

    private func writeStatusLineScript() {
        let scriptContent = """
        #!/bin/bash
        # SwiftClaude Status Line Hook
        # Reads Claude Code status JSON from stdin and writes to status directory

        # Read JSON from stdin
        input=$(cat)

        # Extract session_id for file naming
        session_id=$(echo "$input" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown'))" 2>/dev/null || echo "unknown")

        # Ensure status directory exists
        mkdir -p ~/.claude/swiftclaude-status

        # Write full JSON to session-specific file
        echo "$input" > ~/.claude/swiftclaude-status/${session_id}.json

        # Output simple status line for Claude's display
        model=$(echo "$input" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('model',{}).get('display_name','?'))" 2>/dev/null || echo "?")
        context_pct=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(f\\"{d.get('context_window',{}).get('used_percentage',0):.0f}\\")" 2>/dev/null || echo "0")
        echo "[$model] Context: ${context_pct}%"
        """

        do {
            try scriptContent.write(to: statusLineScript, atomically: true, encoding: .utf8)
            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: statusLineScript.path
            )
        } catch {
            print("ClaudeConfigManager: Failed to write status line script: \(error)")
        }
    }

    private func updateClaudeSettings() {
        let statusLineConfig: [String: Any] = [
            "type": "command",
            "command": "~/.claude/swiftclaude-statusline.sh",
            "padding": 0
        ]

        var settings: [String: Any] = [:]

        // Read existing settings if present
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            do {
                let data = try Data(contentsOf: settingsFile)
                if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = existing
                }
            } catch {
                print("ClaudeConfigManager: Failed to read existing settings: \(error)")
            }
        }

        // Merge in statusLine config
        settings["statusLine"] = statusLineConfig

        // Write updated settings
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsFile)
        } catch {
            print("ClaudeConfigManager: Failed to write settings: \(error)")
        }
    }
}
