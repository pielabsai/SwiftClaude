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

                if let status = status {
                    if status.transcriptPath != nil {
                        Button(action: copyTranscript) {
                            Label("Copy Transcript", systemImage: "text.document")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(action: copyToClipboard) {
                        Label("Copy JSON", systemImage: "doc.on.doc")
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
                HStack(alignment: .top, spacing: 16) {
                    // Parsed fields panel
                    parsedFieldsView(status)
                        .frame(width: 200)

                    Divider()

                    // Raw JSON panel
                    rawJSONView(status)
                }
                .padding(12)
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
    private func rawJSONView(_ status: ClaudeStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Raw JSON")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView([.horizontal, .vertical]) {
                Text(formatJSON(status.rawJSON ?? "{}"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func copyToClipboard() {
        guard let json = status?.rawJSON else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatJSON(json), forType: .string)
    }

    private func copyTranscript() {
        guard let path = status?.transcriptPath else { return }
        let url = URL(fileURLWithPath: path)
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        } catch {
            print("[SC] Failed to read transcript: \(error)")
        }
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
