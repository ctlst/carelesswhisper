import AppKit
import Foundation

final class FocusChecker {
    private let supportedAppNames: Set<String> = ["Claude", "Claude Code", "Codex", "OpenCode"]
    private let supportedBundleIDs: Set<String> = [
        "com.anthropic.claudecode",
        "com.anthropic.claude"
    ]
    private let supportedCLIProcesses: Set<String> = ["claude", "codex", "opencode"]
    private let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.github.wez.wezterm"
    ]

    func currentSupportedApplication() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let name = front.localizedName ?? ""
        let bundle = front.bundleIdentifier ?? ""

        if supportedAppNames.contains(name) || supportedBundleIDs.contains(bundle) {
            return front
        }

        if terminalBundleIDs.contains(bundle) {
            return isSupportedCLIRunning() ? front : nil
        }

        return nil
    }

    func activeDescription() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "unknown" }
        return "\(front.localizedName ?? "unknown") [\(front.bundleIdentifier ?? "unknown")]"
    }

    private func isSupportedCLIRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return output.components(separatedBy: "\n").contains {
                supportedCLIProcesses.contains($0.trimmingCharacters(in: .whitespaces))
            }
        } catch {
            return false
        }
    }
}
