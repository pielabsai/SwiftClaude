import SwiftUI

@main
struct SwiftClaudeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
            }
        }
    }
}
