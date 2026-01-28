import Foundation
import SwiftTerm

@Observable
final class TerminalSession: Identifiable {
    let id = UUID()
    let directory: URL
    var name: String
    var terminalView: LocalProcessTerminalView?

    init(directory: URL) {
        self.directory = directory
        self.name = directory.lastPathComponent
    }
}
