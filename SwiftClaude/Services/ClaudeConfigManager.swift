import Foundation

final class ClaudeConfigManager {
    static let shared = ClaudeConfigManager()

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser
    private var claudeDir: URL { homeDir.appendingPathComponent(".claude") }
    private var hooksDir: URL { claudeDir.appendingPathComponent("hooks") }
    private var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }
    private var statusLineScript: URL { claudeDir.appendingPathComponent("swiftclaude-statusline.sh") }
    private var statusDir: URL { claudeDir.appendingPathComponent("swiftclaude-status") }

    // Hook scripts
    private var sessionStartHook: URL { hooksDir.appendingPathComponent("swiftclaude-session-start.sh") }
    private var stopHook: URL { hooksDir.appendingPathComponent("swiftclaude-stop.sh") }

    private init() {}

    func configureOnLaunch() {
        ensureDirectoriesExist()
        writeStatusLineScript()
        writeHookScripts()
        updateClaudeSettings()
    }

    private func ensureDirectoriesExist() {
        try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
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

        writeScript(content: scriptContent, to: statusLineScript)
    }

    private func writeHookScripts() {
        // SessionStart hook - maps Claude's session ID to SwiftClaude's session ID
        let sessionStartContent = """
        #!/bin/bash
        # SwiftClaude SessionStart Hook
        # Maps Claude's session ID to SwiftClaude's session ID via a mapping file

        # Read JSON from stdin
        input=$(cat)

        # Extract Claude's session_id
        claude_session_id=$(echo "$input" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

        # SWIFTCLAUDE_SESSION_ID is passed via environment when SwiftClaude starts the shell
        if [ -n "$claude_session_id" ] && [ -n "$SWIFTCLAUDE_SESSION_ID" ]; then
            # Write mapping: claude_session_id -> swiftclaude_session_id
            mkdir -p ~/.claude/swiftclaude-status
            echo "$SWIFTCLAUDE_SESSION_ID" > ~/.claude/swiftclaude-status/${claude_session_id}.mapping
        fi

        exit 0
        """

        // Stop hook - writes state file when Claude finishes responding
        let stopContent = """
        #!/bin/bash
        # SwiftClaude Stop Hook
        # Writes state file when Claude finishes responding (waiting for input)

        # Read JSON from stdin
        input=$(cat)

        # Extract Claude's session_id
        claude_session_id=$(echo "$input" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

        if [ -n "$claude_session_id" ]; then
            state_dir=~/.claude/swiftclaude-status
            mapping_file="$state_dir/${claude_session_id}.mapping"

            # Look up the SwiftClaude session ID from the mapping
            if [ -f "$mapping_file" ]; then
                swiftclaude_session_id=$(cat "$mapping_file")
                if [ -n "$swiftclaude_session_id" ]; then
                    # Write state file using SwiftClaude's session ID
                    echo "{\\"state\\":\\"waitingForInput\\",\\"timestamp\\":$(date +%s)}" > "$state_dir/${swiftclaude_session_id}.state"
                fi
            fi
        fi

        exit 0
        """

        writeScript(content: sessionStartContent, to: sessionStartHook)
        writeScript(content: stopContent, to: stopHook)
    }

    private func writeScript(content: String, to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        } catch {
            print("ClaudeConfigManager: Failed to write script \(url.lastPathComponent): \(error)")
        }
    }

    private func updateClaudeSettings() {
        let statusLineConfig: [String: Any] = [
            "type": "command",
            "command": "~/.claude/swiftclaude-statusline.sh",
            "padding": 0
        ]

        // Hook configurations
        let sessionStartHookConfig: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": "~/.claude/hooks/swiftclaude-session-start.sh"
                ]
            ]
        ]

        let stopHookConfig: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": "~/.claude/hooks/swiftclaude-stop.sh"
                ]
            ]
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

        // Merge in hooks config (preserve existing hooks, add ours)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["SessionStart"] = mergeHookArray(existing: hooks["SessionStart"], new: sessionStartHookConfig)
        hooks["Stop"] = mergeHookArray(existing: hooks["Stop"], new: stopHookConfig)
        settings["hooks"] = hooks

        // Write updated settings
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsFile)
        } catch {
            print("ClaudeConfigManager: Failed to write settings: \(error)")
        }
    }

    /// Merges hook configurations, avoiding duplicates of our SwiftClaude hooks
    private func mergeHookArray(existing: Any?, new: [String: Any]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        // Add existing hooks that aren't our SwiftClaude hooks
        if let existingArray = existing as? [[String: Any]] {
            for hookEntry in existingArray {
                if let hooks = hookEntry["hooks"] as? [[String: Any]] {
                    let isSwiftClaudeHook = hooks.contains { hook in
                        if let command = hook["command"] as? String {
                            return command.contains("swiftclaude")
                        }
                        return false
                    }
                    if !isSwiftClaudeHook {
                        result.append(hookEntry)
                    }
                } else {
                    result.append(hookEntry)
                }
            }
        }

        // Add our new hook
        result.append(new)

        return result
    }
}
