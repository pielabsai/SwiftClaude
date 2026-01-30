import SwiftUI

struct DebugView: View {
    @Bindable var session: TerminalSession
    @State private var lastUpdate = Date()

    private var status: ClaudeStatus? { session.status }

    var body: some View {
        let _ = print("[SC] DebugView body - session: \(session.name), id: \(session.id.uuidString.prefix(8))..., state: \(session.currentState)")
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with state indicator
            HStack {
                Text("Debug View")
                    .font(.headline)

                Spacer()

                // Current state indicator
                StateIndicator(state: session.currentState)

                if status != nil {
                    Button(action: copyDebugInfo) {
                        Label("Copy Debug", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Updated: \(lastUpdate.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if let status = status {
                HStack(alignment: .top, spacing: 0) {
                    // Parsed fields panel
                    parsedFieldsView(status)
                        .frame(maxWidth: .infinity)
                        .padding(12)

                    Divider()

                    // Hook State panel
                    hookStateView()
                        .frame(maxWidth: .infinity)
                        .padding(12)

                    Divider()

                    // Transcript Line panel
                    transcriptLineView()
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
            } else {
                ContentUnavailableView {
                    Label("No Status Data", systemImage: "questionmark.circle")
                } description: {
                    Text("Status will appear once Claude Code starts reporting")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: status) { _, _ in
            lastUpdate = Date()
        }
        .onChange(of: session.currentState) { _, _ in
            lastUpdate = Date()
        }
    }

    @ViewBuilder
    private func parsedFieldsView(_ status: ClaudeStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // State section at the top
                fieldGroup("State") {
                    fieldRow("Status", value: session.currentState.displayName)
                    if session.currentState == .waitingForInput {
                        fieldRow("Action", value: "Input needed")
                            .foregroundStyle(.orange)
                    }
                }

                fieldGroup("Session") {
                    fieldRow("ID", value: String(status.sessionId.prefix(8)) + "...")
                }

                if let model = status.model {
                    fieldGroup("Model") {
                        if let name = model.displayName {
                            fieldRow("Name", value: name)
                        }
                        if let id = model.id {
                            fieldRow("ID", value: String(id.prefix(20)))
                        }
                    }
                }

                if let context = status.contextWindow {
                    fieldGroup("Context") {
                        if let used = context.usedPercentage {
                            fieldRow("Used", value: String(format: "%.1f%%", used))
                        }
                        if let remaining = context.remainingPercentage {
                            fieldRow("Remaining", value: String(format: "%.1f%%", remaining))
                        }
                        if let tokens = context.usedTokens {
                            fieldRow("Tokens", value: formatNumber(tokens))
                        }
                    }
                }

                if let cost = status.cost {
                    fieldGroup("Cost") {
                        if let usd = cost.totalCostUsd {
                            fieldRow("Total", value: String(format: "$%.4f", usd))
                        }
                        if let turns = cost.turnCount {
                            fieldRow("Turns", value: "\(turns)")
                        }
                        if let lines = cost.linesAdded {
                            fieldRow("Lines +", value: "\(lines)")
                        }
                        if let lines = cost.linesRemoved {
                            fieldRow("Lines -", value: "\(lines)")
                        }
                    }
                }

                if let workspace = status.workspace {
                    fieldGroup("Workspace") {
                        if let dir = workspace.currentDir {
                            fieldRow("Dir", value: URL(fileURLWithPath: dir).lastPathComponent)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func fieldGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func fieldRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(.caption, design: .monospaced))
    }

    @ViewBuilder
    private func hookStateView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hook State")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView([.horizontal, .vertical]) {
                if let hookJSON = session.rawHookStateJSON {
                    Text(formatJSON(hookJSON))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No hook state received")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func transcriptLineView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transcript Line")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView([.horizontal, .vertical]) {
                if let transcriptLine = session.relevantTranscriptLine {
                    Text(formatJSON(transcriptLine))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No transcript line received")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func copyDebugInfo() {
        var lines: [String] = []
        lines.append("=== Hook State ===")
        if let hookJSON = session.rawHookStateJSON {
            lines.append(formatJSON(hookJSON))
        } else {
            lines.append("(none)")
        }
        lines.append("")
        lines.append("=== Transcript Line ===")
        if let transcriptLine = session.relevantTranscriptLine {
            lines.append(formatJSON(transcriptLine))
        } else {
            lines.append("(none)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return json
        }
        return prettyString
    }

    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
}

struct StateIndicator: View {
    let state: ClaudeState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)

            Text(state.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

#Preview {
    DebugView(session: TerminalSession(directory: URL(fileURLWithPath: "/tmp")))
        .frame(height: 200)
}
