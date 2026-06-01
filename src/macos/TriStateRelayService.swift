import AppKit
import AVFoundation
import Carbon.HIToolbox

#if APP_STORE
let distributionProfile = "app-store"
#else
let distributionProfile = "direct"
#endif

@main
final class TriStateRelayServiceApp: NSObject, NSApplicationDelegate {
    private static weak var sharedDelegate: TriStateRelayServiceApp?

    private let model = MenuBarModel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var playbackRefreshTimer: Timer?
    private var settingsWindowController: SettingsWindowController?
    private var playCurrentLineHotKey: EventHotKeyRef?
    private var openMenuHotKey: EventHotKeyRef?
    private lazy var nativePlayback = NativeSpeechPlayback(model: model) { [weak self] in
        self?.refreshStatusItem()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = TriStateRelayServiceApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.sharedDelegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshStatusItem()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.model.refresh()
            self?.nativePlayback.playNext()
            self?.refreshStatusItem()
            self?.schedulePlaybackRefresh()
        }
        registerGlobalHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        unregisterGlobalHotKeys()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type

        if eventType == .rightMouseUp {
            showMenu()
            return
        }

        model.playNext()
        nativePlayback.playNext()
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    @objc private func ready() {
        model.ready()
        nativePlayback.playNext()
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
        nativePlayback.playNext()
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
        nativePlayback.playNext(line: line)
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

    @objc private func revealLineSource(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.revealSource(line: line)
        refreshStatusItem()
    }

    @objc private func copyLineSource(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? String else {
            return
        }

        model.copySource(line: line)
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
        nativePlayback.playNext(line: line)
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
        nativePlayback.playNext()
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

    private func playCurrentLineFromHotKey() {
        model.refresh()
        refreshStatusItem()
        schedulePlaybackRefresh()
    }

    private func showMenuFromHotKey() {
        model.refresh()
        refreshStatusItem()
        showMenu()
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
            return [lineMenuItem(line: model.status.activeLineTitle, queued: 0, delivered: 0, failed: 0)]
        }

        return lines.map { line in
            lineMenuItem(line: line.line, queued: line.queued, delivered: line.heard, failed: line.failed)
        }
    }

    private func lineMenuItem(line: String, queued: Int, delivered: Int, failed: Int) -> NSMenuItem {
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

            if delivered > 0 {
                let replay = menuItem("Replay Last", action: #selector(replayLineLast(_:)), enabled: true)
                replay.representedObject = line
                submenu.addItem(replay)

                let handled = menuItem("Acknowledge Last", action: #selector(markLineHandled(_:)), enabled: true)
                handled.representedObject = line
                submenu.addItem(handled)

                let clearHeard = menuItem("Clear Delivered", action: #selector(clearLineHeard(_:)), enabled: true)
                clearHeard.representedObject = line
                submenu.addItem(clearHeard)
            }
        }

        if model.status.hasSource(for: line) {
            if submenu.items.count > 0 {
                submenu.addItem(.separator())
            }

            if model.status.hasSourcePath(for: line) {
                let reveal = menuItem("Reveal Source", action: #selector(revealLineSource(_:)), enabled: true)
                reveal.representedObject = line
                submenu.addItem(reveal)
            }

            let copy = menuItem("Copy Source", action: #selector(copyLineSource(_:)), enabled: true)
            copy.representedObject = line
            submenu.addItem(copy)
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

    private func registerGlobalHotKeys() {
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1:
                    TriStateRelayServiceApp.sharedDelegate?.playCurrentLineFromHotKey()
                case 2:
                    TriStateRelayServiceApp.sharedDelegate?.showMenuFromHotKey()
                default:
                    break
                }
            }

            return noErr
        }, 1, [eventSpec], nil, nil)

        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        playCurrentLineHotKey = registerHotKey(keyCode: UInt32(kVK_Space), modifiers: modifiers, id: 1, label: "Control-Option-Command-Space")
        openMenuHotKey = registerHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers, id: 2, label: "Control-Option-Command-V")
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32, label: String) -> EventHotKeyRef? {
        var hotKey = EventHotKeyRef?.none
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: fourCharCode("TSRS"), id: id),
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        if status != noErr {
            NSLog("TSRS failed to register global hotkey \(label): \(status)")
        }

        return hotKey
    }

    private func unregisterGlobalHotKeys() {
        if let playCurrentLineHotKey {
            UnregisterEventHotKey(playCurrentLineHotKey)
        }

        if let openMenuHotKey {
            UnregisterEventHotKey(openMenuHotKey)
        }
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { code, character in
            (code << 8) + OSType(character)
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
#if APP_STORE
        tabView.addTabViewItem(Self.readOnlyTabItem(label: "App Store Profile", message: "External combiner and speech command templates are unavailable in the App Store-safe profile. Relay playback uses Apple speech APIs."))
#else
        tabView.addTabViewItem(Self.tabItem(label: "Inactive Combiner", textView: combinerTextView))
        tabView.addTabViewItem(Self.tabItem(label: "Speech", textView: speechTextView))
#endif

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
#if APP_STORE
        reload()
        onSave()
#else
        model.saveSettings(
            inactiveLineCombinerCommand: combinerTextView.string,
            speechCommand: speechTextView.string
        )
        reload()
        onSave()
#endif
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

    private static func readOnlyTabItem(label: String, message: String) -> NSTabViewItem {
        let textField = NSTextField(labelWithString: message)
        textField.frame = NSRect(x: 16, y: 320, width: 672, height: 48)
        textField.lineBreakMode = .byWordWrapping

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 704, height: 384))
        container.addSubview(textField)

        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = container
        return item
    }
}

final class NativeSpeechPlayback: NSObject, AVSpeechSynthesizerDelegate {
    private let model: MenuBarModel
    private let onChange: () -> Void
    private var currentId: Int?
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = preferredRelayVoice()

    init(model: MenuBarModel, onChange: @escaping () -> Void) {
        self.model = model
        self.onChange = onChange
        super.init()
        synthesizer.delegate = self
    }

    func playNext(line: String? = nil) {
        guard !synthesizer.isSpeaking else {
            return
        }

        guard let claim = model.claimNextForNativeSpeech(line: line) else {
            model.refresh()
            onChange()
            return
        }

        currentId = claim.id

        let utterance = AVSpeechUtterance(string: claim.text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard let id = currentId else {
            return
        }

        model.markNativeSpeechHeard(id: id)
        currentId = nil
        onChange()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard let id = currentId else {
            return
        }

        model.markNativeSpeechFailed(id: id)
        currentId = nil
        onChange()
    }
}

private func preferredRelayVoice() -> AVSpeechSynthesisVoice? {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let preferredNames = ["Samantha", "Ava", "Susan", "Tom", "Allison"]

    for name in preferredNames {
        if let voice = voices.first(where: { $0.name == name && $0.language.hasPrefix("en") }) {
            return voice
        }
    }

    if let enhancedVoice = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .enhanced }) {
        return enhancedVoice
    }

    return AVSpeechSynthesisVoice(language: Locale.current.identifier)
        ?? AVSpeechSynthesisVoice(language: "en-US")
}

final class MenuBarModel {
    private(set) var status = QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], lineSources: [:])

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
        } else {
            runRelay("ready")
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

        refresh()
    }

    func ready() {
        playNext()
    }

    func focus() {
        runRelay("focus")
        refresh()
    }

    func mute() {
        runRelay("mute")
        refresh()
    }

    func unmute() {
        runRelay("unmute")
        refresh()
    }

    func clear() {
        runRelay("clear")
        refresh()
    }

    func clear(line: String) {
        runRelay("clear-line", arguments: ["--line", line])
        refresh()
    }

    func skipNext() {
        runRelay("skip-next")
        refresh()
    }

    func skipNext(line: String) {
        runRelay("skip-next", arguments: ["--line", line])
        refresh()
    }

    func replayLast() {
        runRelay("replay-last")
        playNext()
    }

    func replayLast(line: String) {
        runRelay("replay-last", arguments: ["--line", line])
        setActiveLine(line)
        playActiveLine()
    }

    func markHandled() {
        runRelay("acknowledge")
        refresh()
    }

    func markHandled(line: String) {
        runRelay("acknowledge", arguments: ["--line", line])
        refresh()
    }

    func clearHeard() {
        runRelay("clear-delivered")
        refresh()
    }

    func clearHeard(line: String) {
        runRelay("clear-delivered", arguments: ["--line", line])
        refresh()
    }

    func revealSource(line: String) {
        revealNativeSource(status.lineSources[line]?.path)
        refresh()
    }

    func copySource(line: String) {
        let source = status.lineSources[line]
        copyNativeSource(source?.path ?? source?.url)
        refresh()
    }

    func setActiveLine(_ line: String) {
        runRelay("line", arguments: [line])
        refresh()
    }

    func claimNextForNativeSpeech(line: String? = nil) -> NativeSpeechClaim? {
        var arguments: [String] = []

        if let line {
            arguments = ["--line", line]
        }

        let output = runRelay("app-claim-next", arguments: arguments)

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = json["id"] as? Int,
            let text = json["text"] as? String
        else {
            return nil
        }

        return NativeSpeechClaim(id: id, text: text)
    }

    func markNativeSpeechHeard(id: Int) {
        runRelay("app-mark-heard", arguments: ["--id", String(id)])
        refresh()
    }

    func markNativeSpeechFailed(id: Int) {
        runRelay("app-mark-failed", arguments: ["--id", String(id)])
        refresh()
    }

    func loadSettings() -> SettingsSnapshot {
        let output = runRelay("settings")

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
        runRelay("settings", arguments: [
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
        let output = runRelay("status")

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], lineSources: [:])
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
        let lineSources = parseLineSources(json["lineSources"])

        return QueueStatus(mode: mode, muted: muted, queued: queued, speaking: speaking, heard: heard, inactiveLineCombiner: inactiveLineCombiner, activeLine: activeLine, lines: lines, lineSources: lineSources)
    }

    @discardableResult
    private func runRelay(_ command: String) -> String {
        runRelay(command, arguments: [])
    }

    @discardableResult
    private func runRelay(_ command: String, arguments: [String]) -> String {
        runExecutable(named: "relay", arguments: [command] + arguments)
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
        process.environment = processEnvironment(for: name)
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

    @discardableResult
    private func runExecutableAsync(named name: String, arguments: [String]) -> Process? {
        guard let executableURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(name)
        else {
            return nil
        }
        let process = Process()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = processEnvironment(for: name)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }

    private func processEnvironment(for name: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TSRS_DISTRIBUTION_PROFILE"] = distributionProfile

        if name == "relay" {
            environment["TSRS_PROCESSOR_AUTH"] = "app-owned-processor"
        }

        return environment
    }

    private func revealNativeSource(_ path: String?) {
        guard let path else {
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func copyNativeSource(_ value: String?) {
        guard let value else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct NativeSpeechClaim {
    let id: Int
    let text: String
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
    let lineSources: [String: LineSource]

    func hasSourcePath(for line: String) -> Bool {
        lineSources[line]?.path != nil
    }

    func hasSource(for line: String) -> Bool {
        guard let source = lineSources[line] else {
            return false
        }

        return source.path != nil || source.url != nil
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

struct LineSource {
    let path: String?
    let url: String?
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

private func parseLineSources(_ value: Any?) -> [String: LineSource] {
    guard let rows = value as? [String: [String: Any]] else {
        return [:]
    }

    var sources: [String: LineSource] = [:]

    for (line, source) in rows {
        sources[line] = LineSource(
            path: source["cwd"] as? String,
            url: source["url"] as? String
        )
    }

    return sources
}
