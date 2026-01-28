import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sessionManager = SessionManager()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(
                sessionManager: sessionManager,
                searchText: $searchText,
                isSearchFocused: $isSearchFocused
            )
        } detail: {
            DetailView(
                sessionManager: sessionManager,
                shouldFocusTerminal: !isSearchFocused
            )
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
                    Label(session.name, systemImage: "terminal")
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

struct DetailView: View {
    let sessionManager: SessionManager
    var shouldFocusTerminal: Bool

    var body: some View {
        if let session = sessionManager.selectedSession {
            TerminalView(session: session, requestFocus: shouldFocusTerminal)
                .id(session.id)
        } else {
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
}

#Preview {
    ContentView()
}
