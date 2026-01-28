# SwiftClaude Debug View - Issue Summary

## Original Problem
The Debug View was not updating to show Claude Code's current state (thinking, tool use, responding, waiting for input). It was stuck showing "Idle".

## Architecture Overview

### Data Flow
1. **SwiftClaude** creates a session with a UUID and passes it as `SWIFTCLAUDE_SESSION_ID` env var when launching Claude Code
2. **Claude Code** writes status JSON via the status line hook
3. **Statusline hook** (`~/.claude/swiftclaude-statusline.sh`) writes to `~/.claude/swiftclaude-status/{SWIFTCLAUDE_SESSION_ID}.json`
4. **StatusFileWatcher** monitors this directory and matches files by SwiftClaude's UUID
5. **TranscriptWatcher** monitors the transcript JSONL files to determine real-time state
6. **SessionManager** receives updates with direct UUID matching
7. **DebugView** displays the status and state via SwiftUI observation

### Key Models
- `TerminalSession`: SwiftClaude's session (one per directory/tab)
  - `id`: SwiftClaude's UUID (used for matching status files)
  - `status`: ClaudeStatus from status file
  - `currentState`: ClaudeState (idle/thinking/toolUse/responding/waitingForInput)

- `ClaudeStatus`: Parsed from status JSON (model, cost, context window, workspace)
- `ClaudeState`: Determined by parsing transcript JSONL

## Issues Found and Fixed

### Issue 1: Tab Switching Caused Text Streaming
**Symptom**: Switching tabs caused terminal to re-render all buffered content
**Cause**: `.id(session.id)` modifier on TerminalView forced SwiftUI to recreate the view
**Fix**: Use container view approach - swap terminal views as subviews instead of recreating

### Issue 2: Initialization Race Condition
**Symptom**: Most transcript watches silently failed
**Cause**: `setupStatusFileWatcher()` was called before `setupTranscriptWatcher()`, but status watcher's initial check triggered `handleStatusUpdate` which tried to use the not-yet-created transcript watcher
**Fix**: Reorder init to call `setupTranscriptWatcher()` before `setupStatusFileWatcher()`

### Issue 3: Stale claudeSessionId Persistence
**Symptom**: Sessions were bound to wrong/old Claude sessions
**Cause**: `claudeSessionId` was persisted in UserDefaults, but Claude Code creates new session IDs each run
**Fix**: Remove `claudeSessionId` from CodingKeys - it's now ephemeral

### Issue 4: Session Matching by Wrong claudeSessionId
**Symptom**: State updates couldn't find sessions
**Cause**: Sessions matched by `claudeSessionId` but the IDs kept changing
**Fix**: Match by directory as fallback, store `claudeSessionDirectories` mapping

### Issue 5: Re-assignment to Dead Sessions
**Symptom**: Session gets assigned to Claude sessions with no transcript
**Cause**: Status files exist for old sessions, re-assignment happened regardless of transcript availability
**Fix**: Only re-assign if `FileManager.default.fileExists(atPath: transcriptPath)`

### Issue 6: Old Sessions Overwriting Current State
**Symptom**: Current session's "responding" state gets overwritten by old session's "idle" state
**Cause**: State updates matched by directory fallback, allowing old sessions to update state
**Fix**: Only allow directory fallback for state updates if `session.claudeSessionId == nil`

### Issue 7: Session Assignment to Wrong Claude Session (FIXED)
**Symptom**: Debug View stuck at "idle" even when current Claude session shows tool_use/responding
**Cause**: SwiftClaude was trying to match sessions by directory or Claude Code's session ID, but Claude Code creates new session IDs each run, making reliable matching difficult.

**Root cause**: Complex matching logic trying to associate Claude Code's session IDs with SwiftClaude sessions by directory was brittle and error-prone.

**Solution**: Use SwiftClaude's own session ID instead of relying on Claude Code's session ID.

**Implementation**:
1. Pass `SWIFTCLAUDE_SESSION_ID` environment variable when launching the shell/claude process
2. Update statusline hook to use `$SWIFTCLAUDE_SESSION_ID` for the status filename
3. Status files are now named `{SwiftClaude-UUID}.json` instead of `{Claude-session-id}.json`
4. Direct matching: `sessions.first(where: { $0.id == uuid })` - simple and reliable
5. Removed `claudeSessionId` from TerminalSession entirely - no longer needed

**Key changes**:
- `TerminalView.swift`: Pass environment with `SWIFTCLAUDE_SESSION_ID=session.id.uuidString`
- `~/.claude/swiftclaude-statusline.sh`: Use `$SWIFTCLAUDE_SESSION_ID` if set
- `SessionManager.swift`: Simplified to direct UUID matching
- `TerminalSession.swift`: Removed `claudeSessionId` property

## File Locations

### SwiftClaude App
- `SessionManager.swift` - Central state management, watchers setup
- `TerminalSession.swift` - Session model
- `Services/StatusFileWatcher.swift` - Monitors status JSON files
- `Services/TranscriptWatcher.swift` - Monitors transcript JSONL for state
- `Models/ClaudeStatus.swift` - Status JSON model
- `Models/ClaudeState.swift` - State enum (idle/thinking/etc)
- `Views/DebugView.swift` - Debug panel UI
- `ContentView.swift` - Main UI with DetailView
- `TerminalView.swift` - Terminal wrapper

### Claude Code Files
- `~/.claude/swiftclaude-status/` - Status JSON files (one per Claude session)
- `~/.claude/projects/{encoded-dir}/` - Transcript JSONL files
- `~/.claude/settings.json` - Contains statusLine hook config
- `~/.claude/swiftclaude-statusline.sh` - Hook script that writes status files

## Debugging Tips

All debug logs use `[SC]` prefix for easy filtering in Xcode console.

Key log messages:
- `[SC] Status update for X...` - Status file processed
- `[SC] Starting transcript watch at...` - Transcript monitoring started
- `[SC] Opened transcript fd=N...` - File opened successfully
- `[SC] Failed to open transcript...` - File doesn't exist (old session)
- `[SC] Determined state X...` - State parsed from transcript
- `[SC] Found session by claudeSessionId...` - Exact match
- `[SC] Found session by directory...` - Directory fallback match
- `[SC] Re-assigning session...` - Session switching Claude IDs
- `[SC] Skipping re-assign...` - Blocked due to no transcript
- `[SC] DebugView body...` - View rendering with current state

## Current State Determination Logic

From `TranscriptWatcher.determineState()`:
1. If entry type is "user" → `thinking` (user submitted, Claude processing)
2. If `stop_reason == "end_turn"` → `waitingForInput`
3. If content type is "thinking" → `thinking`
4. If content type is "tool_use" → `toolUse`
5. If content type is "tool_result" → `thinking`
6. If content type is "text" with no stop_reason → `responding`
7. If content type is "text" with stop_reason → `waitingForInput`
8. Default → `idle`
