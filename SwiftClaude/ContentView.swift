import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var sessionManager = sessionManager
        NavigationSplitView {
            SidebarView(
                sessionManager: sessionManager,
                searchText: $searchText,
                isSearchFocused: $isSearchFocused
            )
        } detail: {
            if let session = sessionManager.selectedSession {
                DetailView(
                    session: session,
                    shouldFocusTerminal: !isSearchFocused
                )
            } else {
                EmptySessionView(sessionManager: sessionManager)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(
            isPresented: $sessionManager.showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let accessing = url.startAccessingSecurityScopedResource()
                    sessionManager.createSession(at: url)
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            case .failure(let error):
                print("Failed to select directory: \(error)")
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused {
                searchText = ""
            }
        }
    }
}

struct SidebarView: View {
    @Bindable var sessionManager: SessionManager
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding

    var filteredSessions: [TerminalSession] {
        if searchText.isEmpty {
            return sessionManager.sessions
        }
        return sessionManager.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .focused(isSearchFocused)
                .onKeyPress(.downArrow) {
                    selectNextSession()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectPreviousSession()
                    return .handled
                }
                .onKeyPress(.return) {
                    isSearchFocused.wrappedValue = false
                    return .handled
                }

            List(selection: $sessionManager.selectedSessionID) {
                ForEach(filteredSessions) { session in
                    SessionRowView(session: session)
                        .tag(session.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                sessionManager.deleteSession(session)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { sessionManager.requestNewSession() }) {
                    Label("New Session", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { isSearchFocused.wrappedValue = true }) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private func selectNextSession() {
        let sessions = filteredSessions
        guard !sessions.isEmpty else { return }

        if let currentID = sessionManager.selectedSessionID,
           let currentIndex = sessions.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = min(currentIndex + 1, sessions.count - 1)
            sessionManager.selectedSessionID = sessions[nextIndex].id
        } else {
            sessionManager.selectedSessionID = sessions.first?.id
        }
    }

    private func selectPreviousSession() {
        let sessions = filteredSessions
        guard !sessions.isEmpty else { return }

        if let currentID = sessionManager.selectedSessionID,
           let currentIndex = sessions.firstIndex(where: { $0.id == currentID }) {
            let previousIndex = max(currentIndex - 1, 0)
            sessionManager.selectedSessionID = sessions[previousIndex].id
        } else {
            sessionManager.selectedSessionID = sessions.last?.id
        }
    }
}

struct SessionRowView: View {
    @Bindable var session: TerminalSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.currentState.iconName)
                .foregroundStyle(session.currentState.color)
                .help(session.currentState.displayName)

            Text(session.name)
                .lineLimit(1)
        }
    }
}

struct DetailView: View {
    @Bindable var session: TerminalSession
    var shouldFocusTerminal: Bool
    @State private var showDebugView = false

    var body: some View {
        VStack(spacing: 0) {
            TerminalView(session: session, requestFocus: shouldFocusTerminal)

            if showDebugView {
                Divider()
                DebugView(session: session)
                    .frame(height: 200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDebugView)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showDebugView.toggle() }) {
                    Label("Debug", systemImage: showDebugView ? "ladybug.fill" : "ladybug")
                }
                .keyboardShortcut("d", modifiers: .command)
                .help("Toggle Debug View (⌘D)")
            }
        }
    }
}

struct EmptySessionView: View {
    let sessionManager: SessionManager

    var body: some View {
        ContentUnavailableView {
            Label("No Session Selected", systemImage: "terminal")
        } description: {
            Text("Press ⌘N to create a new session")
        } actions: {
            Button("New Session") {
                sessionManager.requestNewSession()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
