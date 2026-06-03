import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import SQLite3

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
    private var commandPaletteWindowController: CommandPaletteWindowController?
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
            showCommandPalette(initialQuery: "")
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
        button.image = model.status.statusImage
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
        showCommandPalette(initialQuery: "play next")
    }

    private func showCommandPalette(initialQuery: String) {
        model.refresh()
        refreshStatusItem()
        let commands = commandPaletteCommands()

        if commandPaletteWindowController == nil {
            commandPaletteWindowController = CommandPaletteWindowController()
        }

        commandPaletteWindowController?.show(commands: commands, initialQuery: initialQuery)
    }

    private func showMenuFromHotKey() {
        showCommandPalette(initialQuery: "")
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func commandPaletteCommands() -> [CommandPaletteCommand] {
        var commands: [CommandPaletteCommand] = [
            CommandPaletteCommand(title: "Play Next", subtitle: "Release the next queued relay", aliases: ["play", "next"]) { [weak self] in
                self?.model.ready()
                self?.nativePlayback.playNext()
                self?.refreshStatusItem()
                self?.schedulePlaybackRefresh()
            },
            CommandPaletteCommand(title: "Open Settings", subtitle: "Configure TSRS") { [weak self] in
                self?.showSettingsWindow()
            },
            CommandPaletteCommand(title: "Quit", subtitle: "Quit Tri-State Relay Service", aliases: ["exit"]) {
                NSApplication.shared.terminate(nil)
            },
        ]

        if model.status.muted {
            commands.append(CommandPaletteCommand(title: "Unmute", subtitle: "Allow relays to speak") { [weak self] in
                self?.model.unmute()
                self?.refreshStatusItem()
            })
        } else {
            commands.append(CommandPaletteCommand(title: "Mute", subtitle: "Queue relays without speaking") { [weak self] in
                self?.model.mute()
                self?.refreshStatusItem()
            })
        }

        if model.status.mode != "focus" {
            commands.append(CommandPaletteCommand(title: "Focus", subtitle: "Return to quiet focus mode") { [weak self] in
                self?.model.focus()
                self?.refreshStatusItem()
            })
        }

        for line in model.status.menuLines {
            let children = commandPaletteCommands(for: line)

            if !children.isEmpty {
                commands.append(CommandPaletteCommand(title: line.line, subtitle: "\(line.queued) queued, \(line.heard) delivered", aliases: ["line", line.line], children: children))
            }
        }

        return commands
    }

    private func commandPaletteCommands(for line: LineSummary) -> [CommandPaletteCommand] {
        let isActive = line.line == model.status.activeLine
        let activePrefix = isActive ? "Current line" : "Line"
        var commands: [CommandPaletteCommand] = [
            CommandPaletteCommand(title: "Make Current Line", subtitle: "\(activePrefix), \(line.queued) queued", aliases: ["line", line.line]) { [weak self] in
                self?.model.setActiveLine(line.line)
                self?.refreshStatusItem()
            },
        ]

        if line.queued > 0 {
            commands.append(CommandPaletteCommand(title: "Play Next", subtitle: "\(line.queued) queued", aliases: ["play", "next", line.line]) { [weak self] in
                self?.model.setActiveLine(line.line)
                self?.model.playActiveLine()
                self?.nativePlayback.playNext(line: line.line)
                self?.refreshStatusItem()
                self?.schedulePlaybackRefresh()
            })
            commands.append(CommandPaletteCommand(title: "Clear Queue", subtitle: "Clear \(line.queued) queued relays", aliases: ["clear", "queue", line.line]) { [weak self] in
                self?.model.clear(line: line.line)
                self?.refreshStatusItem()
            })

            if isActive {
                commands.append(CommandPaletteCommand(title: "Skip Next", subtitle: "Skip the next queued relay", aliases: ["skip", line.line]) { [weak self] in
                    self?.model.skipNext(line: line.line)
                    self?.refreshStatusItem()
                })
            }
        }

        if line.heard > 0 {
            commands.append(CommandPaletteCommand(title: "Replay Last", subtitle: "Replay latest delivered relay", aliases: ["replay", line.line]) { [weak self] in
                self?.model.replayLast(line: line.line)
                self?.nativePlayback.playNext(line: line.line)
                self?.refreshStatusItem()
                self?.schedulePlaybackRefresh()
            })
            commands.append(CommandPaletteCommand(title: "Acknowledge Last", subtitle: "Mark latest delivered relay acknowledged", aliases: ["acknowledge", "handled", line.line]) { [weak self] in
                self?.model.markHandled(line: line.line)
                self?.refreshStatusItem()
            })
            commands.append(CommandPaletteCommand(title: "Clear Delivered", subtitle: "Clear delivered relays", aliases: ["clear", "delivered", line.line]) { [weak self] in
                self?.model.clearHeard(line: line.line)
                self?.refreshStatusItem()
            })
        }

        if model.status.hasSourcePath(for: line.line) {
            commands.append(CommandPaletteCommand(title: "Reveal Source", subtitle: "Open latest source context", aliases: ["source", "reveal", line.line]) { [weak self] in
                self?.model.revealSource(line: line.line)
                self?.refreshStatusItem()
            })
        }

        if model.status.hasSource(for: line.line) {
            commands.append(CommandPaletteCommand(title: "Copy Source", subtitle: "Copy latest source path or URL", aliases: ["source", "copy", line.line]) { [weak self] in
                self?.model.copySource(line: line.line)
                self?.refreshStatusItem()
            })
        }

        return commands
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

            let clearQueue = menuItem("Clear Queue", action: #selector(clearLine(_:)), enabled: true)
            clearQueue.representedObject = line
            submenu.addItem(clearQueue)
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
    private let voicePopUpButton = NSPopUpButton()
    private let voicePreviewButton = NSButton(title: "Preview", target: nil, action: nil)
    private let voicePreviewSynthesizer = AVSpeechSynthesizer()
    private let settingsTabView = NSTabView()
    private let voiceSectionButton = NSButton(title: "Voice", target: nil, action: nil)
    private let secondarySectionButton = NSButton(title: settingsSecondarySectionTitle, target: nil, action: nil)
    private let voiceSectionRow = SidebarRowView()
    private let secondarySectionRow = SidebarRowView()
    private let voiceIconView = NSImageView(image: sidebarIcon(systemName: "speaker.wave.2"))
    private let secondaryIconView = NSImageView(image: sidebarIcon(systemName: secondarySidebarIconName))
    private let voiceOptions = availableSpeechVoiceOptions()

    init(model: MenuBarModel, onSave: @escaping () -> Void) {
        self.model = model
        self.onSave = onSave

        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        configureSidebarRow(voiceSectionRow, button: voiceSectionButton, iconView: voiceIconView, selected: true)
        configureSidebarRow(secondarySectionRow, button: secondarySectionButton, iconView: secondaryIconView, selected: false)
        settingsTabView.translatesAutoresizingMaskIntoConstraints = false
        settingsTabView.tabViewType = .noTabsNoBorder
        settingsTabView.addTabViewItem(NSTabViewItem(identifier: "Voice"))
#if APP_STORE
        settingsTabView.addTabViewItem(Self.readOnlyTabItem(label: "App Store Profile", message: "External combiner command templates are unavailable in the App Store-safe profile. Relay playback uses Apple speech APIs."))
#else
        settingsTabView.addTabViewItem(Self.tabItem(label: "Inactive Combiner", textView: combinerTextView))
#endif

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 360))
        content.addSubview(sidebar)
        sidebar.addSubview(voiceSectionRow)
        sidebar.addSubview(secondarySectionRow)
        content.addSubview(settingsTabView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tri-State Relay Service Settings"
        window.minSize = NSSize(width: 560, height: 320)
        window.contentView = content
        window.center()

        super.init(window: window)
        window.delegate = self
        settingsTabView.tabViewItem(at: 0).label = "Voice"
        settingsTabView.tabViewItem(at: 0).view = voiceTabView()
        voiceSectionButton.target = self
        voiceSectionButton.action = #selector(selectVoiceSection)
        secondarySectionButton.target = self
        secondarySectionButton.action = #selector(selectSecondarySection)
        voicePopUpButton.target = self
        voicePopUpButton.action = #selector(selectVoice(_:))
        voicePreviewButton.target = self
        voicePreviewButton.action = #selector(previewSelectedVoice(_:))
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 160),
            voiceSectionRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            voiceSectionRow.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            voiceSectionRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 28),
            voiceSectionRow.heightAnchor.constraint(equalToConstant: 38),
            secondarySectionRow.leadingAnchor.constraint(equalTo: voiceSectionRow.leadingAnchor),
            secondarySectionRow.trailingAnchor.constraint(equalTo: voiceSectionRow.trailingAnchor),
            secondarySectionRow.topAnchor.constraint(equalTo: voiceSectionRow.bottomAnchor, constant: 6),
            secondarySectionRow.heightAnchor.constraint(equalTo: voiceSectionRow.heightAnchor),
            settingsTabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            settingsTabView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 28),
            settingsTabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            settingsTabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
        ])
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
        saveCombinerIfNeeded()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func selectVoiceSection() {
        settingsTabView.selectTabViewItem(at: 0)
        updateSidebarSelection(voiceSelected: true)
    }

    @objc private func selectSecondarySection() {
        settingsTabView.selectTabViewItem(at: 1)
        updateSidebarSelection(voiceSelected: false)
    }

    @objc private func selectVoice(_ sender: Any?) {
        model.saveVoiceSetting(voiceIdentifier: selectedVoiceIdentifier())
        onSave()
        previewSelectedVoice(sender)
    }

    @objc private func previewSelectedVoice(_ sender: Any?) {
        voicePreviewSynthesizer.stopSpeaking(at: .immediate)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            let option = self.selectedVoiceOption()
            speakPreview("Tri-state relay service, you changed the voice to \(option.name).", option: option, synthesizer: self.voicePreviewSynthesizer)
        }
    }

    private func reload() {
        let settings = model.loadSettings()
        combinerTextView.string = settings.inactiveLineCombinerCommand
        reloadVoiceMenu(selectedIdentifier: settings.speechVoiceIdentifier)
    }

    private func saveCombinerIfNeeded() {
#if !APP_STORE
        model.saveSettings(
            inactiveLineCombinerCommand: combinerTextView.string,
            voiceIdentifier: selectedVoiceIdentifier()
        )
        onSave()
#endif
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

        let title = NSTextField(labelWithString: label)
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Optional command used to combine inactive-line updates. Leave commented for latest-only behavior.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        let stack = NSStackView(views: [title, subtitle, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 230))
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])

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

    private func voiceTabView() -> NSView {
        let title = NSTextField(labelWithString: "Voice")
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Choose how relay updates sound when TSRS speaks.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0

        let voiceLabel = NSTextField(labelWithString: "Speech voice")
        voiceLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let voiceRow = NSStackView(views: [voicePopUpButton, voicePreviewButton])
        voiceRow.orientation = .horizontal
        voiceRow.alignment = .centerY
        voiceRow.spacing = 8

        let note = NSTextField(labelWithString: "Install additional macOS voices in System Settings > Accessibility > Spoken Content.")
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: 12)
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 0

        let stack = NSStackView(views: [title, subtitle, voiceLabel, voiceRow, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        voicePopUpButton.widthAnchor.constraint(equalToConstant: 340).isActive = true
        voicePreviewButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        note.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 230))
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])

        return container
    }

    private func reloadVoiceMenu(selectedIdentifier: String?) {
        voicePopUpButton.removeAllItems()

        for option in voiceOptions {
            voicePopUpButton.addItem(withTitle: option.title)
            voicePopUpButton.lastItem?.representedObject = option.identifier
        }

        if
            let selectedIdentifier,
            let item = voicePopUpButton.itemArray.first(where: { $0.representedObject as? String == selectedIdentifier }) {
            voicePopUpButton.select(item)
        } else {
            voicePopUpButton.selectItem(at: 0)
        }
    }

    private func selectedVoiceIdentifier() -> String {
        voicePopUpButton.selectedItem?.representedObject as? String ?? defaultSpeechVoiceIdentifier
    }

    private func selectedVoiceOption() -> SpeechVoiceOption {
        voiceOptions.first { $0.identifier == selectedVoiceIdentifier() } ?? defaultSpeechVoiceOption
    }

    private func updateSidebarSelection(voiceSelected: Bool) {
        configureSidebarButton(voiceSectionButton, selected: voiceSelected)
        configureSidebarButton(secondarySectionButton, selected: !voiceSelected)
        voiceIconView.contentTintColor = voiceSelected ? .selectedMenuItemTextColor : .secondaryLabelColor
        secondaryIconView.contentTintColor = voiceSelected ? .secondaryLabelColor : .selectedMenuItemTextColor
        voiceSectionRow.selected = voiceSelected
        secondarySectionRow.selected = !voiceSelected
    }
}

struct CommandPaletteCommand {
    let title: String
    let subtitle: String
    let aliases: [String]
    let children: [CommandPaletteCommand]
    let action: () -> Void

    init(title: String, subtitle: String, aliases: [String] = [], children: [CommandPaletteCommand] = [], action: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.children = children
        self.action = action
    }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.isEmpty {
            return true
        }

        let childText = children.flatMap { [$0.title, $0.subtitle] + $0.aliases }
        let haystack = ([title, subtitle] + aliases + childText).joined(separator: " ").lowercased()
        return haystack.contains(normalized)
    }
}

final class CommandPaletteWindowController: NSWindowController, NSSearchFieldDelegate {
    private let searchField = CommandPaletteSearchField()
    private let resultsStack = NSStackView()
    private var allCommands: [CommandPaletteCommand] = []
    private var rootCommands: [CommandPaletteCommand] = []
    private var filteredCommands: [CommandPaletteCommand] = []
    private var selectedIndex = 0
    private var previousApplication: NSRunningApplication?
    private var navigationStack: [(title: String, commands: [CommandPaletteCommand])] = []

    init() {
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.center()

        super.init(window: panel)
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(commands: [CommandPaletteCommand], initialQuery: String) {
        previousApplication = NSWorkspace.shared.frontmostApplication
        rootCommands = commands
        allCommands = commands
        navigationStack = []
        searchField.stringValue = initialQuery
        searchField.currentEditor()?.selectAll(nil)
        selectedIndex = 0
        filterCommands()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.searchField)
            self?.searchField.selectText(nil)
        }
    }

    private func buildContent() {
        guard let window else {
            return
        }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        searchField.placeholderString = "Search TSRS actions..."
        searchField.delegate = self

        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 6
        resultsStack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.cornerRadius = 18
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = resolvedColor(.windowBackgroundColor).cgColor
        content.addSubview(searchField)
        content.addSubview(resultsStack)
        window.contentView = content

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            searchField.heightAnchor.constraint(equalToConstant: 34),
            resultsStack.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            resultsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            resultsStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
        ])
    }

    func controlTextDidChange(_ obj: Notification) {
        selectedIndex = 0
        filterCommands()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handleCommand(commandSelector)
    }

    private func handleCommand(_ selector: Selector) -> Bool {
        if selector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(1)
            return true
        }

        if selector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(-1)
            return true
        }

        if selector == #selector(NSResponder.insertNewline(_:)) {
            executeSelected()
            return true
        }

        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if navigationStack.isEmpty {
                close()
                restorePreviousApplication()
            } else {
                navigateBack()
            }
            return true
        }

        if selector == #selector(NSResponder.deleteBackward(_:)), searchField.stringValue.isEmpty, !navigationStack.isEmpty {
            navigateBack()
            return true
        }

        return false
    }

    private func filterCommands() {
        filteredCommands = allCommands.filter { $0.matches(searchField.stringValue) }

        if selectedIndex >= filteredCommands.count {
            selectedIndex = max(0, filteredCommands.count - 1)
        }

        renderResults()
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredCommands.isEmpty else {
            return
        }

        selectedIndex = min(max(selectedIndex + delta, 0), filteredCommands.count - 1)
        renderResults()
    }

    private func executeSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else {
            return
        }

        let command = filteredCommands[selectedIndex]
        if command.children.isEmpty {
            close()
            command.action()
            restorePreviousApplication()
        } else {
            navigationStack.append((title: command.title, commands: allCommands))
            allCommands = command.children
            searchField.stringValue = ""
            selectedIndex = 0
            filterCommands()
        }
    }

    private func navigateBack() {
        guard let previous = navigationStack.popLast() else {
            return
        }

        allCommands = previous.commands
        searchField.stringValue = ""
        selectedIndex = 0
        filterCommands()
    }

    private func restorePreviousApplication() {
        guard let previousApplication, previousApplication != NSRunningApplication.current else {
            return
        }

        let application = previousApplication
        self.previousApplication = nil
        DispatchQueue.main.async {
            application.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func renderResults() {
        for view in resultsStack.arrangedSubviews {
            resultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if filteredCommands.isEmpty {
            resultsStack.addArrangedSubview(resultRow(title: "No actions found", subtitle: "Try another query", selected: false))
            return
        }

        for (index, command) in filteredCommands.prefix(5).enumerated() {
            resultsStack.addArrangedSubview(resultRow(title: command.title, subtitle: command.subtitle, selected: index == selectedIndex))
        }
    }

    private func resultRow(title: String, subtitle: String, selected: Bool) -> NSView {
        let row = PaletteResultRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.selected = selected

        let displayTitle = subtitle == "submenu" ? "\(title) ›" : title
        let titleField = NSTextField(labelWithString: displayTitle)
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = selected ? resolvedColor(.selectedMenuItemTextColor) : resolvedColor(.labelColor)
        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = selected ? resolvedColor(.selectedMenuItemTextColor) : resolvedColor(.secondaryLabelColor)
        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),
            row.widthAnchor.constraint(equalToConstant: 524),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }
}

final class CommandPaletteSearchField: NSSearchField {}

final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

final class PaletteResultRowView: NSView {
    var selected = false {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard selected else {
            return
        }

        resolvedColor(.controlAccentColor).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: 8, yRadius: 8).fill()
    }
}

private func configureSidebarButton(_ button: NSButton, selected: Bool) {
    button.bezelStyle = .regularSquare
    button.isBordered = false
    button.alignment = .left
    button.font = NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
    button.contentTintColor = selected ? .selectedMenuItemTextColor : .labelColor
    button.imagePosition = .noImage
}

private func configureSidebarRow(_ row: SidebarRowView, button: NSButton, iconView: NSImageView, selected: Bool) {
    row.translatesAutoresizingMaskIntoConstraints = false
    row.selected = selected
    iconView.translatesAutoresizingMaskIntoConstraints = false
    button.translatesAutoresizingMaskIntoConstraints = false
    configureSidebarButton(button, selected: selected)
    row.addSubview(iconView)
    row.addSubview(button)
    NSLayoutConstraint.activate([
        iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
        iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        iconView.widthAnchor.constraint(equalToConstant: 24),
        iconView.heightAnchor.constraint(equalToConstant: 24),
        button.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
        button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
        button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])
}

final class SidebarRowView: NSView {
    var selected = false {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard selected else {
            return
        }

        resolvedColor(.controlAccentColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}

private func sidebarIcon(systemName: String) -> NSImage {
    let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        ?? NSImage(size: NSSize(width: 18, height: 18))
    image.isTemplate = true
    return image
}

private func resolvedColor(_ color: NSColor) -> NSColor {
    NSAppearance.current = NSApp.effectiveAppearance
    defer {
        NSAppearance.current = nil
    }
    return color.usingColorSpace(.deviceRGB) ?? color
}

#if APP_STORE
private let settingsSecondarySectionTitle = "App Store"
private let secondarySidebarIconName = "lock.shield"
#else
private let settingsSecondarySectionTitle = "Combiner"
private let secondarySidebarIconName = "text.bubble"
#endif

private let defaultStaleRelayAgeMinutes = 30

final class NativeSpeechPlayback: NSObject, AVSpeechSynthesizerDelegate {
    private let model: MenuBarModel
    private let onChange: () -> Void
    private let inputCaptureSensor: InputCaptureSensing
    private var currentId: Int?
    private var currentProcess: Process?
    private let synthesizer = AVSpeechSynthesizer()

    init(model: MenuBarModel, inputCaptureSensor: InputCaptureSensing = DefaultInputCaptureSensor(), onChange: @escaping () -> Void) {
        self.model = model
        self.inputCaptureSensor = inputCaptureSensor
        self.onChange = onChange
        super.init()
        synthesizer.delegate = self
    }

    func playNext(line: String? = nil) {
        guard !synthesizer.isSpeaking, currentProcess == nil else {
            return
        }

        if inputCaptureSensor.isInputCaptureActive() {
            model.refresh()
            onChange()
            return
        }

        guard let claim = model.claimNextForNativeSpeech(line: line) else {
            model.refresh()
            onChange()
            return
        }

        currentId = claim.id

        speak(claim)
    }

    private func speak(_ claim: NativeSpeechClaim) {
#if APP_STORE
        let utterance = AVSpeechUtterance(string: claim.text)
        utterance.voice = preferredRelayVoice(identifier: model.loadSettings().speechVoiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1
        synthesizer.speak(utterance)
#else
        let option = speechVoiceOption(identifier: model.loadSettings().speechVoiceIdentifier)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = sayArguments(text: claim.text, option: option)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if process.terminationStatus == 0 {
                    self.model.markNativeSpeechHeard(id: claim.id)
                } else {
                    self.model.markNativeSpeechFailed(id: claim.id)
                }

                self.currentId = nil
                self.currentProcess = nil
                self.onChange()
            }
        }

        do {
            currentProcess = process
            try process.run()
        } catch {
            currentProcess = nil
            model.markNativeSpeechFailed(id: claim.id)
            currentId = nil
            onChange()
        }
#endif
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

protocol InputCaptureSensing {
    func isInputCaptureActive() -> Bool
}

struct DefaultInputCaptureSensor: InputCaptureSensing {
    func isInputCaptureActive() -> Bool {
        guard let deviceID = defaultInputDeviceID() else {
            return false
        }

        var isRunning: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &isRunning
        )

        return status == noErr && isRunning != 0
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        return deviceID
    }
}

struct SpeechVoiceOption {
    let identifier: String
    let name: String
    let title: String
}

private let systemSayVoiceIdentifier = "system-say-default"
private let defaultSpeechVoiceIdentifier = systemSayVoiceIdentifier
private let defaultSpeechVoiceOption = SpeechVoiceOption(identifier: systemSayVoiceIdentifier, name: "System Default", title: "System Default (say)")

private func availableSpeechVoiceOptions() -> [SpeechVoiceOption] {
#if APP_STORE
    return availableRelayVoices().map { voice in
        SpeechVoiceOption(identifier: voice.identifier, name: voice.name, title: "\(voice.name) (\(voice.language))")
    }
#else
    return directSpeechVoiceOptions
#endif
}

private func speechVoiceOption(identifier: String?) -> SpeechVoiceOption {
    availableSpeechVoiceOptions().first { $0.identifier == identifier } ?? defaultSpeechVoiceOption
}

private func sayArguments(text: String, option: SpeechVoiceOption) -> [String] {
    if option.identifier.hasPrefix("say:") {
        return ["-v", option.name, text]
    }

    return [text]
}

private func speakPreview(_ text: String, option: SpeechVoiceOption, synthesizer: AVSpeechSynthesizer) {
#if APP_STORE
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = preferredRelayVoice(identifier: option.identifier)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
#else
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = sayArguments(text: text, option: option)
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
#endif
}

private func availableRelayVoices() -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") && !noveltyVoiceIdentifiers.contains($0.identifier) }
        .sorted { left, right in
            if left.language == "en-US", right.language != "en-US" {
                return true
            }

            if left.language != "en-US", right.language == "en-US" {
                return false
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
}

private func preferredRelayVoice(identifier: String?) -> AVSpeechSynthesisVoice? {
    let voices = availableRelayVoices()

    if let identifier, let voice = voices.first(where: { $0.identifier == identifier }) {
        return voice
    }

    let preferredIdentifiers = [
        defaultSpeechVoiceIdentifier,
        "com.apple.voice.premium.en-US.Samantha",
        "com.apple.voice.enhanced.en-US.Samantha",
        "com.apple.voice.compact.en-US.Ava",
        "com.apple.voice.premium.en-US.Ava",
        "com.apple.voice.enhanced.en-US.Ava",
    ]

    for identifier in preferredIdentifiers {
        if let voice = voices.first(where: { $0.identifier == identifier }) {
            return voice
        }
    }

    let preferredNames = ["Samantha", "Ava", "Allison", "Susan", "Tom"]

    for name in preferredNames {
        if let voice = voices.first(where: { $0.name == name && $0.language.hasPrefix("en") }) {
            return voice
        }
    }

    if let enhancedVoice = voices.first(where: { $0.quality == .enhanced && $0.name != "Alex" }) {
        return enhancedVoice
    }

    if let nonAlexEnglishVoice = voices.first(where: { $0.name != "Alex" }) {
        return nonAlexEnglishVoice
    }

    return AVSpeechSynthesisVoice(identifier: defaultSpeechVoiceIdentifier)
        ?? AVSpeechSynthesisVoice(language: "en-US")
}

private let noveltyVoiceIdentifiers = Set([
    "com.apple.speech.synthesis.voice.Albert",
    "com.apple.speech.synthesis.voice.BadNews",
    "com.apple.speech.synthesis.voice.Bahh",
    "com.apple.speech.synthesis.voice.Bells",
    "com.apple.speech.synthesis.voice.Boing",
    "com.apple.speech.synthesis.voice.Bubbles",
    "com.apple.speech.synthesis.voice.Cellos",
    "com.apple.speech.synthesis.voice.Deranged",
    "com.apple.speech.synthesis.voice.GoodNews",
    "com.apple.speech.synthesis.voice.Hysterical",
    "com.apple.speech.synthesis.voice.Junior",
    "com.apple.speech.synthesis.voice.Organ",
    "com.apple.speech.synthesis.voice.Princess",
    "com.apple.speech.synthesis.voice.Ralph",
    "com.apple.speech.synthesis.voice.Trinoids",
    "com.apple.speech.synthesis.voice.Whisper",
    "com.apple.speech.synthesis.voice.Zarvox",
])

private let noveltySayVoiceNames = Set([
    "Albert",
    "Bad News",
    "Bahh",
    "Bells",
    "Boing",
    "Bubbles",
    "Cellos",
    "Good News",
    "Jester",
    "Junior",
    "Organ",
    "Ralph",
    "Superstar",
    "Trinoids",
    "Whisper",
    "Wobble",
    "Zarvox",
])

private let directSpeechVoiceOptions = [
    defaultSpeechVoiceOption,
    SpeechVoiceOption(identifier: "say:Samantha", name: "Samantha", title: "Samantha"),
    SpeechVoiceOption(identifier: "say:Alex", name: "Alex", title: "Alex"),
    SpeechVoiceOption(identifier: "say:Daniel", name: "Daniel", title: "Daniel"),
    SpeechVoiceOption(identifier: "say:Karen", name: "Karen", title: "Karen"),
    SpeechVoiceOption(identifier: "say:Moira", name: "Moira", title: "Moira"),
]

final class MenuBarModel {
    private(set) var status = QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], lineSources: [:])
    private let store = NativeRelayStore(profile: distributionProfile)

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
            store.setMode("ready")
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
        store.setMode("focus")
        refresh()
    }

    func mute() {
        store.setMuted(true)
        refresh()
    }

    func unmute() {
        store.setMuted(false)
        refresh()
    }

    func clear() {
        store.clear()
        refresh()
    }

    func clear(line: String) {
        store.clearQueued(line: line)
        refresh()
    }

    func skipNext() {
        store.skipNextQueued()
        refresh()
    }

    func skipNext(line: String) {
        store.skipNextQueued(line: line)
        refresh()
    }

    func replayLast() {
        store.replayLatestHeard()
        playNext()
    }

    func replayLast(line: String) {
        store.replayLatestHeard(line: line)
        setActiveLine(line)
        playActiveLine()
    }

    func markHandled() {
        store.markLatestHeardHandled()
        refresh()
    }

    func markHandled(line: String) {
        store.markLatestHeardHandled(line: line)
        refresh()
    }

    func clearHeard() {
        store.clearHeard()
        refresh()
    }

    func clearHeard(line: String) {
        store.clearHeard(line: line)
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
        store.setActiveLine(line)
        refresh()
    }

    func claimNextForNativeSpeech(line: String? = nil) -> NativeSpeechClaim? {
        store.claimNextForNativeSpeech(line: line)
    }

    func markNativeSpeechHeard(id: Int) {
        store.markNativeSpeechHeard(id: id)
        refresh()
    }

    func markNativeSpeechFailed(id: Int) {
        store.markNativeSpeechFailed(id: id)
        refresh()
    }

    func loadSettings() -> SettingsSnapshot {
        store.loadSettings()
    }

    func saveSettings(inactiveLineCombinerCommand: String, voiceIdentifier: String) {
        store.saveSettings(
            inactiveLineCombinerCommand: inactiveLineCombinerCommand,
            voiceIdentifier: voiceIdentifier
        )
        refresh()
    }

    func saveVoiceSetting(voiceIdentifier: String) {
        store.saveVoiceIdentifier(voiceIdentifier)
        refresh()
    }

    func refresh() {
        status = loadStatus()
    }

    private func loadStatus() -> QueueStatus {
        store.loadStatus()
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

struct NativeRelay {
    let id: Int
    let line: String
    let message: String
    let type: String
    let priority: String
    let status: String
    let createdAt: String
    let updatedAt: String
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

    var statusImage: NSImage? {
        if !muted && speaking == 0 {
            return trayImage(accessibilityDescription: title, includesRedBars: queued > 0)
        }

        guard queued > 0 else {
            let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
            image?.isTemplate = true
            return image
        }

        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        image?.isTemplate = true
        return image
    }
}

private func trayImage(accessibilityDescription: String, includesRedBars: Bool) -> NSImage {
    let size = NSSize(width: 20, height: 20)
    let image = NSImage(size: size)
    image.accessibilityDescription = accessibilityDescription
    image.isTemplate = includesRedBars ? false : true

    image.lockFocus()
    defer {
        image.unlockFocus()
    }

    if let tray = NSImage(systemSymbolName: "tray", accessibilityDescription: accessibilityDescription)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)) {
        resolvedColor(.labelColor).set()
        tray.draw(in: NSRect(x: 0.5, y: 1, width: 19, height: 17), from: .zero, operation: .sourceAtop, fraction: 1)
    }

    guard includesRedBars else {
        return image
    }

    let redBars = NSBezierPath()
    redBars.lineWidth = 1.25
    redBars.lineCapStyle = .round
    resolvedColor(.systemRed).setStroke()
    redBars.move(to: NSPoint(x: 7.4, y: 13.2))
    redBars.line(to: NSPoint(x: 11.8, y: 13.2))
    redBars.move(to: NSPoint(x: 6.1, y: 11.2))
    redBars.line(to: NSPoint(x: 13.1, y: 11.2))
    redBars.stroke()

    return image
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
    let speechVoiceIdentifier: String?
}

final class NativeRelayStore {
    private let profile: String
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    init(profile: String) {
        self.profile = profile
    }

    func loadSettings() -> SettingsSnapshot {
        withDatabase { database in
            let settings = loadRawSettings(database)
            return SettingsSnapshot(
                inactiveLineCombinerCommand: inactiveLineCombinerCommand(settings),
                speechVoiceIdentifier: speechVoiceIdentifier(settings)
            )
        } ?? defaultSettings()
    }

    func loadStatus() -> QueueStatus {
        withWriteDatabase { database in
            expireStaleRelays(database)
            let settings = loadRawSettings(database)
            let counts = countByStatus(database)
            return QueueStatus(
                mode: playbackMode(settings["mode"]),
                muted: settings["muted"] == "true",
                queued: counts["queued"] ?? 0,
                speaking: counts["speaking"] ?? 0,
                heard: counts["heard"] ?? 0,
                inactiveLineCombiner: inactiveLineCombiner(settings),
                activeLine: settings["active_line"],
                lines: lineSummaries(database),
                lineSources: latestSourceContextsByLine(database)
            )
        } ?? defaultStatus()
    }

    func setMode(_ mode: String) {
        guard mode == "ready" || mode == "focus" else {
            NSLog("TSRS native store rejected invalid mode: \(mode)")
            return
        }

        write { database in
            setSetting(database, key: "mode", value: mode)
        }
    }

    func setMuted(_ muted: Bool) {
        write { database in
            setSetting(database, key: "muted", value: String(muted))
        }
    }

    func setActiveLine(_ line: String) {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            NSLog("TSRS native store rejected empty active line")
            return
        }

        write { database in
            setSetting(database, key: "active_line", value: normalized)
        }
    }

    func saveSettings(inactiveLineCombinerCommand: String, voiceIdentifier: String) {
        guard profile != "app-store" else {
            saveVoiceIdentifier(voiceIdentifier)
            return
        }

        write { database in
            setSetting(database, key: "inactive_line_combiner_command", value: resetBlankCommand(inactiveLineCombinerCommand, fallback: defaultInactiveLineCombinerCommand))
            setSetting(database, key: "speech_voice_identifier", value: voiceIdentifier)
        }
    }

    func saveVoiceIdentifier(_ voiceIdentifier: String) {
        guard availableSpeechVoiceOptions().contains(where: { $0.identifier == voiceIdentifier }) else {
            NSLog("TSRS native store rejected unavailable voice identifier: \(voiceIdentifier)")
            return
        }

        write { database in
            setSetting(database, key: "speech_voice_identifier", value: voiceIdentifier)
        }
    }

    func clear() {
        write { database in
            execute(database, """
                DELETE FROM relays
                WHERE status IN ('queued', 'heard', 'handled', 'skipped', 'expired', 'failed')
            """)
        }
    }

    func clearHeard(line: String? = nil) {
        write { database in
            execute(database, """
                DELETE FROM relays
                WHERE status = 'heard' AND (? IS NULL OR line = ?)
            """, [line, line])
        }
    }

    func clearQueued(line: String) {
        write { database in
            execute(database, """
                DELETE FROM relays
                WHERE status = 'queued' AND line = ?
            """, [line])
        }
    }

    func skipNextQueued(line: String? = nil) {
        write { database in
            _ = markFirstMatchingStatus(database, from: "queued", to: "skipped", line: line)
        }
    }

    func markLatestHeardHandled(line: String? = nil) {
        write { database in
            _ = markLatestMatchingStatus(database, from: "heard", to: "handled", line: line)
        }
    }

    func replayLatestHeard(line: String? = nil) {
        write { database in
            _ = markLatestMatchingStatus(database, from: "heard", to: "queued", line: line)
        }
    }

    func claimNextForNativeSpeech(line: String? = nil) -> NativeSpeechClaim? {
        writeResult { database in
            expireStaleRelays(database)
            failStaleSpeaking(database)
            let relay: NativeRelay?

            if let line {
                relay = claimNextForLine(database, line: line)
            } else {
                let settings = loadRawSettings(database)
                if let activeLine = settings["active_line"], queuedCount(database, line: activeLine) > 0 {
                    relay = claimNextForLine(database, line: activeLine)
                } else {
                    relay = claimNextForSpeech(database)
                }
            }

            guard let relay else {
                return nil
            }

            return NativeSpeechClaim(
                id: relay.id,
                text: spokenText(relay, includeLine: shouldPrefixSpokenLine(database, line: relay.line))
            )
        }
    }

    func markNativeSpeechHeard(id: Int) {
        write { database in
            guard let relay = markStatus(database, id: id, status: "heard") else {
                NSLog("TSRS native store could not mark missing relay heard: \(id)")
                return
            }

            recordSpokenLine(database, line: relay.line)
        }
    }

    func markNativeSpeechFailed(id: Int) {
        write { database in
            if markStatus(database, id: id, status: "failed") == nil {
                NSLog("TSRS native store could not mark missing relay failed: \(id)")
            }
        }
    }

    private func withDatabase<T>(_ read: (OpaquePointer) -> T?) -> T? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databasePath(), &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }

        sqlite3_busy_timeout(database, 2_000)
        defer {
            sqlite3_close(database)
        }

        return read(database)
    }

    private func write(_ mutation: (OpaquePointer) -> Void) {
        _ = withWriteDatabase { database in
            mutation(database)
            return true
        }
    }

    private func writeResult<T>(_ mutation: (OpaquePointer) -> T?) -> T? {
        withWriteDatabase(mutation)
    }

    private func withWriteDatabase<T>(_ mutation: (OpaquePointer) -> T?) -> T? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databasePath(), &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                NSLog("TSRS native store write open failed: \(sqliteError(database))")
                sqlite3_close(database)
            } else {
                NSLog("TSRS native store write open failed")
            }
            return nil
        }

        sqlite3_busy_timeout(database, 2_000)
        defer {
            sqlite3_close(database)
        }

        return mutation(database)
    }

    private func loadRawSettings(_ database: OpaquePointer) -> [String: String] {
        var settings: [String: String] = [:]
        query(database, "SELECT key, value FROM settings") { statement in
            guard let key = columnString(statement, 0), let value = columnString(statement, 1) else {
                return
            }

            settings[key] = value
        }

        return settings
    }

    private func countByStatus(_ database: OpaquePointer) -> [String: Int] {
        var counts = [
            "queued": 0,
            "speaking": 0,
            "heard": 0,
            "handled": 0,
            "skipped": 0,
            "expired": 0,
            "failed": 0,
        ]

        query(database, """
            SELECT status, COUNT(*) AS count
            FROM relays
            GROUP BY status
        """) { statement in
            guard let status = columnString(statement, 0) else {
                return
            }

            counts[status] = Int(sqlite3_column_int(statement, 1))
        }

        return counts
    }

    private func lineSummaries(_ database: OpaquePointer) -> [LineSummary] {
        var lines: [LineSummary] = []

        query(database, """
            SELECT
              line,
              SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued,
              SUM(CASE WHEN status = 'heard' THEN 1 ELSE 0 END) AS heard,
              SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY line
            HAVING queued > 0 OR heard > 0 OR failed > 0
            ORDER BY queued DESC, heard DESC, failed DESC, line ASC
        """) { statement in
            guard let line = columnString(statement, 0) else {
                return
            }

            lines.append(LineSummary(
                line: line,
                queued: Int(sqlite3_column_int(statement, 1)),
                heard: Int(sqlite3_column_int(statement, 2)),
                failed: Int(sqlite3_column_int(statement, 3))
            ))
        }

        return lines
    }

    private func latestSourceContextsByLine(_ database: OpaquePointer) -> [String: LineSource] {
        var sources: [String: LineSource] = [:]

        query(database, """
            SELECT id, line, session, app, cwd, url
            FROM relays AS source
            WHERE (cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL)
              AND id = (
                SELECT id
                FROM relays AS candidate
                WHERE candidate.line = source.line
                  AND (
                    candidate.cwd IS NOT NULL
                    OR candidate.url IS NOT NULL
                    OR candidate.app IS NOT NULL
                    OR candidate.session IS NOT NULL
                  )
                ORDER BY created_at DESC, id DESC
                LIMIT 1
              )
            ORDER BY line ASC
        """) { statement in
            guard let line = columnString(statement, 1) else {
                return
            }

            sources[line] = LineSource(
                path: columnString(statement, 4),
                url: columnString(statement, 5)
            )
        }

        return sources
    }

    private func query(_ database: OpaquePointer, _ sql: String, _ values: [String?] = [], row: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }

    private func execute(_ database: OpaquePointer, _ sql: String, _ values: [String?] = []) {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            NSLog("TSRS native store prepare failed: \(sqliteError(database))")
            if let statement {
                sqlite3_finalize(statement)
            }
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)
        let result = sqlite3_step(statement)

        if result != SQLITE_DONE {
            NSLog("TSRS native store execute failed: \(sqliteError(database))")
        }
    }

    private func returningRelay(_ database: OpaquePointer, _ sql: String, _ values: [String?]) -> NativeRelay? {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            NSLog("TSRS native store returning prepare failed: \(sqliteError(database))")
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return mapRelay(statement)
        case SQLITE_DONE:
            return nil
        default:
            NSLog("TSRS native store returning step failed: \(sqliteError(database))")
            return nil
        }
    }

    private func setSetting(_ database: OpaquePointer, key: String, value: String) {
        execute(database, """
            INSERT INTO settings (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, [key, value])
    }

    private func queuedCount(_ database: OpaquePointer, line: String) -> Int {
        var count = 0
        query(database, """
            SELECT COUNT(*) AS count
            FROM relays
            WHERE status = 'queued' AND line = ?
        """, [line]) { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        return count
    }

    private func claimNextForSpeech(_ database: OpaquePointer) -> NativeRelay? {
        let settings = loadRawSettings(database)

        guard settings["muted"] != "true", playbackMode(settings["mode"]) == "ready" else {
            return nil
        }

        let relay = returningRelay(database, """
            UPDATE relays
            SET status = 'speaking', updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = 'queued'
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status, created_at, updated_at
        """, [nowString()])

        if relay != nil {
            setSetting(database, key: "mode", value: "focus")
        }

        return relay
    }

    private func claimNextForLine(_ database: OpaquePointer, line: String) -> NativeRelay? {
        let settings = loadRawSettings(database)

        guard settings["muted"] != "true" else {
            return nil
        }

        return returningRelay(database, """
            UPDATE relays
            SET status = 'speaking', updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = 'queued' AND line = ?
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status, created_at, updated_at
        """, [nowString(), line])
    }

    private func markFirstMatchingStatus(_ database: OpaquePointer, from: String, to: String, line: String?) -> NativeRelay? {
        returningRelay(database, """
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = ? AND (? IS NULL OR line = ?)
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status, created_at, updated_at
        """, [to, nowString(), from, line, line])
    }

    private func markLatestMatchingStatus(_ database: OpaquePointer, from: String, to: String, line: String?) -> NativeRelay? {
        returningRelay(database, """
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = ? AND (? IS NULL OR line = ?)
              ORDER BY updated_at DESC, id DESC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status, created_at, updated_at
        """, [to, nowString(), from, line, line])
    }

    private func markStatus(_ database: OpaquePointer, id: Int, status: String) -> NativeRelay? {
        returningRelay(database, """
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = ?
            RETURNING id, line, message, type, priority, status, created_at, updated_at
        """, [status, nowString(), String(id)])
    }

    private func failStaleSpeaking(_ database: OpaquePointer) {
        let staleBefore = nowString(addingMilliseconds: -60_000)
        execute(database, """
            UPDATE relays
            SET status = 'failed', updated_at = ?
            WHERE status = 'speaking' AND updated_at <= ?
        """, [nowString(), staleBefore])
    }

    private func expireStaleRelays(_ database: OpaquePointer) {
        let staleBefore = nowString(addingMilliseconds: -TimeInterval(defaultStaleRelayAgeMinutes * 60 * 1000))
        execute(database, """
            UPDATE relays
            SET status = 'expired', updated_at = ?
            WHERE (
              status IN ('heard', 'failed') AND updated_at <= ?
            ) OR (
              status = 'queued'
              AND priority != 'high'
              AND type IN ('update', 'complete')
              AND created_at <= ?
            )
        """, [nowString(), staleBefore, staleBefore])
    }

    private func recordSpokenLine(_ database: OpaquePointer, line: String) {
        let escapedLine = line
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        setSetting(database, key: "last_spoken_line", value: "{\"line\":\"\(escapedLine)\",\"spokenAt\":\"\(nowString())\"}")
    }

    private func shouldPrefixSpokenLine(_ database: OpaquePointer, line: String) -> Bool {
        guard
            let value = loadRawSettings(database)["last_spoken_line"],
            let data = value.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let lastLine = parsed["line"] as? String,
            let spokenAt = parsed["spokenAt"] as? String
        else {
            return true
        }

        if lastLine != line {
            return true
        }

        guard let date = timestampFormatter.date(from: spokenAt) else {
            return true
        }

        return Date().timeIntervalSince(date) >= 60
    }

    private func spokenText(_ relay: NativeRelay, includeLine: Bool) -> String {
        let linePrefix = includeLine ? "\(relay.line). " : ""
        let typePrefix = relay.type == "update" ? "" : "\(relay.type). "
        return "\(linePrefix)\(typePrefix)\(relay.message)"
    }

    private func nowString(addingMilliseconds milliseconds: TimeInterval = 0) -> String {
        timestampFormatter.string(from: Date(timeIntervalSinceNow: milliseconds / 1000))
    }

    private func mapRelay(_ statement: OpaquePointer) -> NativeRelay {
        NativeRelay(
            id: Int(sqlite3_column_int(statement, 0)),
            line: columnString(statement, 1) ?? "",
            message: columnString(statement, 2) ?? "",
            type: columnString(statement, 3) ?? "update",
            priority: columnString(statement, 4) ?? "normal",
            status: columnString(statement, 5) ?? "queued",
            createdAt: columnString(statement, 6) ?? "",
            updatedAt: columnString(statement, 7) ?? ""
        )
    }

    private func bind(_ values: [String?], to statement: OpaquePointer) {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)

            if let value {
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, position)
            }
        }
    }

    private func inactiveLineCombiner(_ settings: [String: String]) -> String {
        if profile == "app-store" {
            return "none"
        }

        return commandIsEnabled(settings["inactive_line_combiner_command"] ?? defaultInactiveLineCombinerCommand) ? "custom" : "none"
    }

    private func inactiveLineCombinerCommand(_ settings: [String: String]) -> String {
        if profile == "app-store" {
            return appStoreUnavailableCommand("inactive-line combiner")
        }

        return settings["inactive_line_combiner_command"] ?? defaultInactiveLineCombinerCommand
    }

    private func speechVoiceIdentifier(_ settings: [String: String]) -> String? {
        let identifier = settings["speech_voice_identifier"] ?? defaultSpeechVoiceIdentifier

        if availableSpeechVoiceOptions().contains(where: { $0.identifier == identifier }) {
            return identifier
        }

        return defaultSpeechVoiceIdentifier
    }
}

private func databasePath() -> String {
    let environment = ProcessInfo.processInfo.environment

    if let path = environment["TSRS_DB_PATH"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return path
    }

    let home = environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Application Support/Tri-State Relay Service/relay.db"
}

private func defaultStatus() -> QueueStatus {
    QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], lineSources: [:])
}

private func defaultSettings() -> SettingsSnapshot {
    SettingsSnapshot(inactiveLineCombinerCommand: "", speechVoiceIdentifier: defaultSpeechVoiceIdentifier)
}

private func playbackMode(_ value: String?) -> String {
    value == "ready" ? "ready" : "focus"
}

private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else {
        return nil
    }

    return String(cString: text)
}

private func commandIsEnabled(_ template: String) -> Bool {
    let commandText = template
        .split(whereSeparator: \.isNewline)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        .joined(separator: " ")

    return !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func resetBlankCommand(_ value: String, fallback: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
}

private func sqliteError(_ database: OpaquePointer) -> String {
    guard let message = sqlite3_errmsg(database) else {
        return "unknown SQLite error"
    }

    return String(cString: message)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func appStoreUnavailableCommand(_ feature: String) -> String {
    "# External \(feature) command execution is unavailable in the App Store-safe profile."
}

private let defaultInactiveLineCombinerCommand = """
# Inactive line combiner command.
# Leave this commented to use latest-only inactive-line behavior.
# The command must print a JSON object: {"action":"replace|promote|drop","type":"update|blocked|complete","priority":"low|normal|high","message":"short relay"}
# Placeholders are inserted as single argv values, not shell-expanded.
#
# llm CLI: https://github.com/simonw/llm
# llm prompt <input> --system <system> --no-stream --no-log
#
# apfel CLI: https://github.com/Arthur-Ficial/apfel
# apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>
"""

private let defaultSpeechCommand = """
# Speech command.
# /usr/bin/say ships with macOS, so no extra install is required.
# Placeholders are inserted as single argv values, not shell-expanded.
/usr/bin/say <message>
"""
