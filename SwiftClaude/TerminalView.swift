import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let session: TerminalSession
    var requestFocus: Bool = false

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let terminalView = getOrCreateTerminalView()

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        if requestFocus {
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let terminalView = getOrCreateTerminalView()

        // Check if we need to swap the terminal view
        if let currentTerminal = container.subviews.first as? LocalProcessTerminalView,
           currentTerminal === terminalView {
            // Same terminal, just handle focus
            if requestFocus {
                DispatchQueue.main.async {
                    terminalView.window?.makeFirstResponder(terminalView)
                }
            }
            return
        }

        // Different session - swap the terminal view
        container.subviews.forEach { $0.removeFromSuperview() }

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        if requestFocus {
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }
    }

    private func getOrCreateTerminalView() -> LocalProcessTerminalView {
        if let existingView = session.terminalView {
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
}
