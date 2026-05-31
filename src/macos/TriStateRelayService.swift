import SwiftUI

@main
struct TriStateRelayServiceApp: App {
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        MenuBarExtra(model.status.title, systemImage: model.status.systemImage) {
            Text(model.status.title)
            Divider()
            Button("Ready") {
                model.ready()
            }
            .disabled(model.status.mode == "ready")
            Button("Focus") {
                model.focus()
            }
            .disabled(model.status.mode == "focus")
            Divider()
            Button("Mute") {
                model.mute()
            }
            .disabled(model.status.muted)
            Button("Unmute") {
                model.unmute()
            }
            .disabled(!model.status.muted)
            Divider()
            Button("Clear Queue") {
                model.clear()
            }
            .disabled(model.status.queued == 0)
            Button("Skip Next") {
                model.skipNext()
            }
            .disabled(model.status.queued == 0)
            Button("Replay Last") {
                model.replayLast()
            }
            .disabled(model.status.heard == 0)
            Button("Mark Handled") {
                model.markHandled()
            }
            .disabled(model.status.heard == 0)
            Button("Clear Heard") {
                model.clearHeard()
            }
            .disabled(model.status.heard == 0)
            Divider()
            Button("Reveal Source") {
                model.revealSource()
            }
            .disabled(!model.status.hasSourcePath)
            Button("Copy Source") {
                model.copySource()
            }
            .disabled(!model.status.hasSource)
            Button("Refresh Status") {
                model.refresh()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class MenuBarModel: ObservableObject {
    @Published var status = QueueStatus(mode: "focus", muted: false, queued: 0, heard: 0, sourcePath: nil, sourceURL: nil)
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.processIfReady()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func ready() {
        runVoicemail("ready")
        processIfReady()
    }

    func focus() {
        runVoicemail("focus")
        refresh()
    }

    func mute() {
        runVoicemail("mute")
        refresh()
    }

    func unmute() {
        runVoicemail("unmute")
        processIfReady()
    }

    func clear() {
        runVoicemail("clear")
        refresh()
    }

    func skipNext() {
        runVoicemail("skip-next")
        refresh()
    }

    func replayLast() {
        runVoicemail("replay-last")
        refresh()
    }

    func markHandled() {
        runVoicemail("mark-handled")
        refresh()
    }

    func clearHeard() {
        runVoicemail("clear-heard")
        refresh()
    }

    func revealSource() {
        runVoicemail("reveal-source")
        refresh()
    }

    func copySource() {
        runVoicemail("copy-source")
        refresh()
    }

    func refresh() {
        status = loadStatus()
    }

    func processIfReady() {
        let currentStatus = loadStatus()

        if currentStatus.shouldProcess {
            runProcessor()
        }

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
        guard let executableURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(name)
        else {
            return "missing app executable URL"
        }
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

    var shouldProcess: Bool {
        mode == "ready" && !muted && queued > 0
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
