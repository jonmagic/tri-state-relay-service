import AppKit

@main
final class TriStateRelayServiceApp: NSObject, NSApplicationDelegate {
    private let model = MenuBarModel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var playbackRefreshTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = TriStateRelayServiceApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshStatusItem()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.model.refresh()
            self?.refreshStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type

        if eventType == .rightMouseUp {
            showMenu()
            return
        }

        model.playNext()
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    @objc private func ready() {
        model.ready()
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    @objc private func focus() {
        model.focus()
        refreshStatusItem()
    }

    @objc private func mute() {
        model.mute()
        refreshStatusItem()
    }

    @objc private func unmute() {
        model.unmute()
        refreshStatusItem()
    }

    @objc private func clear() {
        model.clear()
        refreshStatusItem()
    }

    @objc private func skipNext() {
        model.skipNext()
        refreshStatusItem()
    }

    @objc private func replayLast() {
        model.replayLast()
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    @objc private func markHandled() {
        model.markHandled()
        refreshStatusItem()
    }

    @objc private func clearHeard() {
        model.clearHeard()
        refreshStatusItem()
    }

    @objc private func revealSource() {
        model.revealSource()
        refreshStatusItem()
    }

    @objc private func copySource() {
        model.copySource()
        refreshStatusItem()
    }

    @objc private func refresh() {
        model.refresh()
        refreshStatusItem()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = NSImage(systemSymbolName: model.status.systemImage, accessibilityDescription: model.status.title)
    }

    private func showMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: model.status.title, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Play Next", action: #selector(ready), enabled: model.status.canPlayFromMenu))
        menu.addItem(menuItem("Focus", action: #selector(focus), enabled: model.status.mode != "focus"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Mute", action: #selector(mute), enabled: !model.status.muted))
        menu.addItem(menuItem("Unmute", action: #selector(unmute), enabled: model.status.muted))
        menu.addItem(.separator())
        menu.addItem(menuItem("Clear Queue", action: #selector(clear), enabled: model.status.queued > 0))
        menu.addItem(menuItem("Skip Next", action: #selector(skipNext), enabled: model.status.queued > 0))
        menu.addItem(menuItem("Replay Last", action: #selector(replayLast), enabled: model.status.heard > 0))
        menu.addItem(menuItem("Mark Handled", action: #selector(markHandled), enabled: model.status.heard > 0))
        menu.addItem(menuItem("Clear Heard", action: #selector(clearHeard), enabled: model.status.heard > 0))
        menu.addItem(.separator())
        menu.addItem(menuItem("Reveal Source", action: #selector(revealSource), enabled: model.status.hasSourcePath))
        menu.addItem(menuItem("Copy Source", action: #selector(copySource), enabled: model.status.hasSource))
        menu.addItem(menuItem("Refresh Status", action: #selector(refresh), enabled: true))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", action: #selector(quit), enabled: true))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func schedulePlaybackRefresh() {
        playbackRefreshTimer?.invalidate()
        playbackRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.model.refresh()
            self.refreshStatusItem()

            if self.model.status.speaking == 0 {
                timer.invalidate()
            }
        }
    }
}

final class MenuBarModel {
    private(set) var status = QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, sourcePath: nil, sourceURL: nil)

    init() {
        refresh()
    }

    func playNext() {
        let currentStatus = loadStatus()

        if currentStatus.muted || currentStatus.queued == 0 {
            status = currentStatus
            return
        }

        runVoicemail("ready")
        runProcessorAsync()
        refresh()
    }

    func ready() {
        playNext()
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
        refresh()
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
        playNext()
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

    private func loadStatus() -> QueueStatus {
        let output = runVoicemail("status")

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, sourcePath: nil, sourceURL: nil)
        }

        let mode = json["mode"] as? String ?? "focus"
        let muted = json["muted"] as? Bool ?? false
        let queued = intValue(json["queueCount"])
        let counts = json["counts"] as? [String: Any] ?? [:]
        let speaking = intValue(counts["speaking"])
        let heard = intValue(counts["heard"])
        let source = json["source"] as? [String: Any]
        let cwd = source?["cwd"] as? String
        let url = source?["url"] as? String

        return QueueStatus(mode: mode, muted: muted, queued: queued, speaking: speaking, heard: heard, sourcePath: cwd, sourceURL: url)
    }

    @discardableResult
    private func runVoicemail(_ command: String) -> String {
        runExecutable(named: "voicemail", arguments: [command])
    }

    @discardableResult
    private func runProcessor() -> String {
        runExecutable(named: "voicemail-processor", arguments: [])
    }

    private func runProcessorAsync() {
        runExecutableAsync(named: "voicemail-processor", arguments: [])
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

    private func runExecutableAsync(named name: String, arguments: [String]) {
        guard let executableURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(name)
        else {
            return
        }
        let process = Process()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return
        }
    }
}

struct QueueStatus {
    let mode: String
    let muted: Bool
    let queued: Int
    let speaking: Int
    let heard: Int
    let sourcePath: String?
    let sourceURL: String?

    var hasSourcePath: Bool {
        sourcePath != nil
    }

    var hasSource: Bool {
        sourcePath != nil || sourceURL != nil
    }

    var canPlayFromMenu: Bool {
        !muted && queued > 0
    }

    var title: String {
        if speaking > 0 {
            return "TSRS speaking"
        }

        if muted {
            return "TSRS muted (\(queued))"
        }

        if queued > 0 {
            return "TSRS ready (\(queued))"
        }

        return "TSRS focus (0)"
    }

    var systemImage: String {
        if speaking > 0 {
            return "speaker.wave.2"
        }

        if muted {
            return "speaker.slash"
        }

        if queued > 0 {
            return "tray.full"
        }

        return "tray"
    }
}

private func intValue(_ value: Any?) -> Int {
    if let int = value as? Int {
        return int
    }

    if let number = value as? NSNumber {
        return number.intValue
    }

    return 0
}
