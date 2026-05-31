import AppKit

@main
final class TriStateRelayServiceApp: NSObject, NSApplicationDelegate {
    private let model = MenuBarModel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var playbackRefreshTimer: Timer?
    private var settingsWindowController: SettingsWindowController?

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

    @objc private func clearLine(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.clear(line: line)
        refreshStatusItem()
    }

    @objc private func skipLineNext(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.skipNext(line: line)
        refreshStatusItem()
    }

    @objc private func replayLineLast(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.replayLast(line: line)
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    @objc private func markLineHandled(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.markHandled(line: line)
        refreshStatusItem()
    }

    @objc private func clearLineHeard(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.clearHeard(line: line)
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

    @objc private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: model) { [weak self] in
                self?.refreshStatusItem()
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
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
        if model.status.muted {
            menu.addItem(menuItem("Unmute", action: #selector(unmute), enabled: true))
        } else {
            menu.addItem(menuItem("Mute", action: #selector(mute), enabled: true))
        }
        menu.addItem(menuItem("Settings...", action: #selector(showSettingsWindow), enabled: true))
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
                let skip = menuItem("Skip Next", action: #selector(skipLineNext(_:)), enabled: true)
                skip.representedObject = line
                submenu.addItem(skip)

                let clearQueue = menuItem("Clear Queue", action: #selector(clearLine(_:)), enabled: true)
                clearQueue.representedObject = line
                submenu.addItem(clearQueue)
            }

            if heard > 0 {
                let replay = menuItem("Replay Last", action: #selector(replayLineLast(_:)), enabled: true)
                replay.representedObject = line
                submenu.addItem(replay)

                let handled = menuItem("Mark Handled", action: #selector(markLineHandled(_:)), enabled: true)
                handled.representedObject = line
                submenu.addItem(handled)

                let clearHeard = menuItem("Clear Heard", action: #selector(clearLineHeard(_:)), enabled: true)
                clearHeard.representedObject = line
                submenu.addItem(clearHeard)
            }
        }

        if submenu.items.isEmpty {
            submenu.addItem(NSMenuItem(title: "No line actions available", action: nil, keyEquivalent: ""))
        }
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

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: MenuBarModel
    private let onSave: () -> Void
    private let combinerTextView = NSTextView()
    private let speechTextView = NSTextView()

    init(model: MenuBarModel, onSave: @escaping () -> Void) {
        self.model = model
        self.onSave = onSave

        let tabView = NSTabView(frame: NSRect(x: 0, y: 48, width: 720, height: 432))
        tabView.autoresizingMask = [.width, .height]
        tabView.addTabViewItem(Self.tabItem(label: "Inactive Combiner", textView: combinerTextView))
        tabView.addTabViewItem(Self.tabItem(label: "Speech", textView: speechTextView))

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.frame = NSRect(x: 608, y: 12, width: 88, height: 28)
        saveButton.bezelStyle = .rounded

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        content.addSubview(tabView)
        content.addSubview(saveButton)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tri-State Relay Service Settings"
        window.contentView = content
        window.center()

        super.init(window: window)
        window.delegate = self
        saveButton.target = self
        saveButton.action = #selector(save)
        reload()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func save() {
        model.saveSettings(
            inactiveLineCombinerCommand: combinerTextView.string,
            speechCommand: speechTextView.string
        )
        reload()
        onSave()
    }

    private func reload() {
        let settings = model.loadSettings()
        combinerTextView.string = settings.inactiveLineCombinerCommand
        speechTextView.string = settings.speechCommand
    }

    private static func tabItem(label: String, textView: NSTextView) -> NSTabViewItem {
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        let scrollView = NSScrollView(frame: NSRect(x: 12, y: 12, width: 680, height: 360))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 704, height: 384))
        container.addSubview(scrollView)

        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = container
        return item
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

        if let line = currentStatus.nextQueuedLine {
            setActiveLine(line)
            runProcessorAsync(line: line)
        } else {
            runVoicemail("ready")
            runProcessorAsync()
        }
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

    func clear(line: String) {
        runVoicemail("clear-line", arguments: ["--line", line])
        refresh()
    }

    func skipNext() {
        runVoicemail("skip-next")
        refresh()
    }

    func skipNext(line: String) {
        runVoicemail("skip-next", arguments: ["--line", line])
        refresh()
    }

    func replayLast() {
        runVoicemail("replay-last")
        playNext()
    }

    func replayLast(line: String) {
        runVoicemail("replay-last", arguments: ["--line", line])
        setActiveLine(line)
        playActiveLine()
    }

    func markHandled() {
        runVoicemail("mark-handled")
        refresh()
    }

    func markHandled(line: String) {
        runVoicemail("mark-handled", arguments: ["--line", line])
        refresh()
    }

    func clearHeard() {
        runVoicemail("clear-heard")
        refresh()
    }

    func clearHeard(line: String) {
        runVoicemail("clear-heard", arguments: ["--line", line])
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

    func setActiveLine(_ line: String) {
        runVoicemail("line", arguments: [line])
        refresh()
    }

    func loadSettings() -> SettingsSnapshot {
        let output = runVoicemail("settings")

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return SettingsSnapshot(inactiveLineCombinerCommand: "", speechCommand: "/usr/bin/say <message>")
        }

        return SettingsSnapshot(
            inactiveLineCombinerCommand: json["inactiveLineCombinerCommand"] as? String ?? "",
            speechCommand: json["speechCommand"] as? String ?? "/usr/bin/say <message>"
        )
    }

    func saveSettings(inactiveLineCombinerCommand: String, speechCommand: String) {
        runVoicemail("settings", arguments: [
            "--combiner-command",
            inactiveLineCombinerCommand,
            "--speech-command",
            speechCommand,
        ])
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

    var nextQueuedLine: String? {
        lines.first { $0.queued > 0 }?.line
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

struct SettingsSnapshot {
    let inactiveLineCombinerCommand: String
    let speechCommand: String
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
