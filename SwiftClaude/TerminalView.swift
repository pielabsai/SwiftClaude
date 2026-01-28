import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let session: TerminalSession
    var requestFocus: Bool = false

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        if let existingView = session.terminalView {
            if requestFocus {
                DispatchQueue.main.async {
                    existingView.window?.makeFirstResponder(existingView)
                }
            }
            return existingView
        }

        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        terminalView.startProcess(
            executable: shellPath,
            args: ["-l", "-i"],
            environment: nil,
            execName: nil
        )

        let command = "cd '\(session.directory.path)' && claude\n"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            terminalView.send(txt: command)
        }

        session.terminalView = terminalView
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if requestFocus {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}
