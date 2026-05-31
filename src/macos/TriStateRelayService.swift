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
            self?.model.playActiveLine()
            self?.refreshStatusItem()
            self?.schedulePlaybackRefresh()
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

    @objc private func selectLine(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.setActiveLine(line)
        refreshStatusItem()
    }

    @objc private func playLine(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.setActiveLine(line)
        model.playActiveLine()
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    @objc private func useNoCombiner() {
        model.setInactiveLineCombiner("none")
        refreshStatusItem()
    }

    @objc private func useLLMCombiner() {
        model.setInactiveLineCombiner("llm")
        refreshStatusItem()
    }

    @objc private func useApfelCombiner() {
        model.setInactiveLineCombiner("apfel")
        refreshStatusItem()
    }

    @objc private func linePlayNext() {
        model.ready()
        refreshStatusItem()
        schedulePlaybackRefresh()
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
        for item in lineMenuItems() {
            menu.addItem(item)
        }
        if model.status.hasSource {
            menu.addItem(.separator())

            if model.status.hasSourcePath {
                menu.addItem(menuItem("Reveal Source", action: #selector(revealSource), enabled: true))
            }

            menu.addItem(menuItem("Copy Source", action: #selector(copySource), enabled: true))
        }
        menu.addItem(.separator())
        menu.addItem(settingsMenuItem())
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

    private func lineMenuItems() -> [NSMenuItem] {
        let lines = model.status.menuLines

        if lines.isEmpty {
            return [lineMenuItem(line: model.status.activeLineTitle, queued: 0, heard: 0, failed: 0)]
        }

        return lines.map { line in
            lineMenuItem(line: line.line, queued: line.queued, heard: line.heard, failed: line.failed)
        }
    }

    private func lineMenuItem(line: String, queued: Int, heard: Int, failed: Int) -> NSMenuItem {
        let suffix = line == model.status.activeLine ? " ✓" : ""
        let item = NSMenuItem(title: "\(line) (\(queued) queued)\(suffix)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if line != model.status.activeLine {
            let makeCurrent = menuItem("Make Current Line", action: #selector(selectLine(_:)), enabled: true)
            makeCurrent.representedObject = line
            submenu.addItem(makeCurrent)
        }

        if queued > 0 {
            if !submenu.items.isEmpty {
                submenu.addItem(.separator())
            }
            let play = menuItem("Play Next", action: #selector(playLine(_:)), enabled: true)
            play.representedObject = line
            submenu.addItem(play)
        }

        if line == model.status.activeLine && (model.status.mode != "focus" || model.status.queued > 0 || model.status.heard > 0) {
            if submenu.items.count > 0 {
                submenu.addItem(.separator())
            }

            if model.status.mode != "focus" {
                submenu.addItem(menuItem("Focus", action: #selector(focus), enabled: true))
            }

            if queued > 0 {
                submenu.addItem(menuItem("Skip Next", action: #selector(skipNext), enabled: true))
                submenu.addItem(menuItem("Clear Queue", action: #selector(clear), enabled: true))
            }

            if heard > 0 {
                submenu.addItem(menuItem("Replay Last", action: #selector(replayLast), enabled: true))
                submenu.addItem(menuItem("Mark Handled", action: #selector(markHandled), enabled: true))
                submenu.addItem(menuItem("Clear Heard", action: #selector(clearHeard), enabled: true))
            }
        }

        if submenu.items.isEmpty {
            submenu.addItem(NSMenuItem(title: "No line actions available", action: nil, keyEquivalent: ""))
        }
        item.submenu = submenu

        return item
    }

    private func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if model.status.muted {
            submenu.addItem(menuItem("Unmute", action: #selector(unmute), enabled: true))
        } else {
            submenu.addItem(menuItem("Mute", action: #selector(mute), enabled: true))
        }
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "Inactive Combiner: \(model.status.inactiveLineCombiner)", action: nil, keyEquivalent: ""))
        submenu.addItem(menuItem("Use Latest Only", action: #selector(useNoCombiner), enabled: model.status.inactiveLineCombiner != "none"))
        submenu.addItem(menuItem("Use llm", action: #selector(useLLMCombiner), enabled: model.status.inactiveLineCombiner != "llm"))
        submenu.addItem(menuItem("Use apfel", action: #selector(useApfelCombiner), enabled: model.status.inactiveLineCombiner != "apfel"))
        item.submenu = submenu

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
    private(set) var status = QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], sourcePath: nil, sourceURL: nil)

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

    func playActiveLine() {
        let currentStatus = loadStatus()

        guard
            !currentStatus.muted,
            currentStatus.speaking == 0,
            let activeLine = currentStatus.activeLine,
            currentStatus.queuedCount(for: activeLine) > 0
        else {
            status = currentStatus
            return
        }

        runProcessorAsync(line: activeLine)
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

    func setInactiveLineCombiner(_ combiner: String) {
        runVoicemail("combiner", arguments: ["--tool", combiner])
        refresh()
    }

    func setActiveLine(_ line: String) {
        runVoicemail("line", arguments: [line])
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
            return QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], sourcePath: nil, sourceURL: nil)
        }

        let mode = json["mode"] as? String ?? "focus"
        let muted = json["muted"] as? Bool ?? false
        let inactiveLineCombiner = json["inactiveLineCombiner"] as? String ?? "none"
        let activeLine = json["activeLine"] as? String
        let queued = intValue(json["queueCount"])
        let counts = json["counts"] as? [String: Any] ?? [:]
        let speaking = intValue(counts["speaking"])
        let heard = intValue(counts["heard"])
        let lines = parseLines(json["lines"])
        let source = json["source"] as? [String: Any]
        let cwd = source?["cwd"] as? String
        let url = source?["url"] as? String

        return QueueStatus(mode: mode, muted: muted, queued: queued, speaking: speaking, heard: heard, inactiveLineCombiner: inactiveLineCombiner, activeLine: activeLine, lines: lines, sourcePath: cwd, sourceURL: url)
    }

    @discardableResult
    private func runVoicemail(_ command: String) -> String {
        runVoicemail(command, arguments: [])
    }

    @discardableResult
    private func runVoicemail(_ command: String, arguments: [String]) -> String {
        runExecutable(named: "voicemail", arguments: [command] + arguments)
    }

    @discardableResult
    private func runProcessor() -> String {
        runExecutable(named: "voicemail-processor", arguments: [])
    }

    private func runProcessorAsync() {
        runExecutableAsync(named: "voicemail-processor", arguments: [])
    }

    private func runProcessorAsync(line: String) {
        runExecutableAsync(named: "voicemail-processor", arguments: ["--line", line])
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
    let inactiveLineCombiner: String
    let activeLine: String?
    let lines: [LineSummary]
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

    var activeLineTitle: String {
        activeLine ?? "None"
    }

    var menuLines: [LineSummary] {
        if lines.contains(where: { $0.line == activeLine }) {
            return lines
        }

        if let activeLine {
            return [LineSummary(line: activeLine, queued: 0, heard: 0, failed: 0)] + lines
        }

        return lines
    }

    func queuedCount(for line: String) -> Int {
        lines.first { $0.line == line }?.queued ?? 0
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

struct LineSummary {
    let line: String
    let queued: Int
    let heard: Int
    let failed: Int
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

private func parseLines(_ value: Any?) -> [LineSummary] {
    guard let rows = value as? [[String: Any]] else {
        return []
    }

    return rows.compactMap { row in
        guard let line = row["line"] as? String else {
            return nil
        }

        return LineSummary(
            line: line,
            queued: intValue(row["queued"]),
            heard: intValue(row["heard"]),
            failed: intValue(row["failed"]),
        )
    }
}
