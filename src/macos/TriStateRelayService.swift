import SwiftUI

@main
struct TriStateRelayServiceApp: App {
    @State private var status = QueueStatus(mode: "focus", muted: false, queued: 0, heard: 0, sourcePath: nil, sourceURL: nil)

    var body: some Scene {
        MenuBarExtra(status.title, systemImage: status.systemImage) {
            Text(status.title)
            Divider()
            Button("Ready") {
                runVoicemail("ready")
                runProcessor()
                refresh()
            }
            .disabled(status.mode == "ready")
            Button("Focus") {
                runVoicemail("focus")
                refresh()
            }
            .disabled(status.mode == "focus")
            Divider()
            Button("Mute") {
                runVoicemail("mute")
                refresh()
            }
            .disabled(status.muted)
            Button("Unmute") {
                runVoicemail("unmute")
                refresh()
            }
            .disabled(!status.muted)
            Divider()
            Button("Clear Queue") {
                runVoicemail("clear")
                refresh()
            }
            .disabled(status.queued == 0)
            Button("Skip Next") {
                runVoicemail("skip-next")
                refresh()
            }
            .disabled(status.queued == 0)
            Button("Replay Last") {
                runVoicemail("replay-last")
                refresh()
            }
            .disabled(status.heard == 0)
            Button("Mark Handled") {
                runVoicemail("mark-handled")
                refresh()
            }
            .disabled(status.heard == 0)
            Button("Clear Heard") {
                runVoicemail("clear-heard")
                refresh()
            }
            .disabled(status.heard == 0)
            Divider()
            Button("Reveal Source") {
                runVoicemail("reveal-source")
                refresh()
            }
            .disabled(!status.hasSourcePath)
            Button("Copy Source") {
                runVoicemail("copy-source")
                refresh()
            }
            .disabled(!status.hasSource)
            Button("Refresh Status") {
                refresh()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        refresh()
    }

    private func refresh() {
        status = loadStatus()
    }

    private func loadStatus() -> QueueStatus {
        let output = runVoicemail("status")

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return QueueStatus(mode: "focus", muted: false, queued: 0, heard: 0, sourcePath: nil, sourceURL: nil)
        }

        let mode = json["mode"] as? String ?? "focus"
        let muted = json["muted"] as? Bool ?? false
        let queued = json["queueCount"] as? Int ?? 0
        let counts = json["counts"] as? [String: Int] ?? [:]
        let heard = counts["heard"] ?? 0
        let source = json["source"] as? [String: Any]
        let cwd = source?["cwd"] as? String
        let url = source?["url"] as? String

        return QueueStatus(mode: mode, muted: muted, queued: queued, heard: heard, sourcePath: cwd, sourceURL: url)
    }

    @discardableResult
    private func runVoicemail(_ command: String) -> String {
        runExecutable(named: "voicemail", arguments: [command])
    }

    @discardableResult
    private func runProcessor() -> String {
        runExecutable(named: "voicemail-processor", arguments: [])
    }

    private func runExecutable(named name: String, arguments: [String]) -> String {
        let executableURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(name)
        let process = Process()
        let output = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct QueueStatus {
    let mode: String
    let muted: Bool
    let queued: Int
    let heard: Int
    let sourcePath: String?
    let sourceURL: String?

    var hasSourcePath: Bool {
        sourcePath != nil
    }

    var hasSource: Bool {
        sourcePath != nil || sourceURL != nil
    }

    var title: String {
        if muted {
            return "TSRS muted (\(queued))"
        }

        if mode == "ready" {
            return "TSRS ready (\(queued))"
        }

        return "TSRS focus (\(queued))"
    }

    var systemImage: String {
        if muted {
            return "speaker.slash"
        }

        if queued > 0 {
            return "tray.full"
        }

        return "tray"
    }
}
