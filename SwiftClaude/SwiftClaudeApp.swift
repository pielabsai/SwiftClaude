import SwiftUI

@main
struct SwiftClaudeApp: App {
    @State private var sessionManager = SessionManager()

    init() {
        // Auto-configure Claude Code settings on app launch
        ClaudeConfigManager.shared.configureOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    sessionManager.save()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
            }
        }
    }
}
