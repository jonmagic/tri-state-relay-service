import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import ServiceManagement
import SQLite3

#if APP_STORE
let distributionProfile = "app-store"
#else
let distributionProfile = "direct"
#endif

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? relayCliVersion

@main
final class TriStateRelayServiceApp: NSObject, NSApplicationDelegate {
    private static weak var sharedDelegate: TriStateRelayServiceApp?

    private let model = MenuBarModel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var playbackRefreshTimer: Timer?
    private var settingsWindowController: SettingsWindowController?
    private var commandPaletteWindowController: CommandPaletteWindowController?
    private var commandPaletteHotKey: EventHotKeyRef?
    private var commandPaletteHotKeyEventHandler: EventHandlerRef?
    private lazy var nativePlayback = NativeSpeechPlayback(model: model) { [weak self] in
        self?.model.refresh()
        self?.refreshStatusItem()
    }

    private lazy var commandPaletteCommandsProvider: () -> [CommandPaletteCommand] = { [weak self] in
        guard let self else {
            return []
        }

        self.model.refresh()
        self.refreshStatusItem()
        return self.commandPaletteCommands()
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
#if !APP_STORE
        if model.needsFirstStartSetup() {
            showSettingsWindow()
        }
#else
        if model.needsFirstStartSetup() {
            showSettingsWindow()
        }
#endif
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

    @objc private func live() {
        model.live()
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
            settingsWindowController = SettingsWindowController(model: model, onInstallRelayCli: { [weak self] in
#if !APP_STORE
                self?.installRelayCli()
#endif
            }, onShortcutRecordingChanged: { [weak self] isRecording in
                if isRecording {
                    self?.unregisterGlobalHotKeys()
                } else {
                    self?.registerGlobalHotKeys()
                }
            }) { [weak self] in
                self?.refreshStatusItem()
                self?.registerGlobalHotKeys()
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        refreshStatusItem()
    }

#if !APP_STORE
    @objc private func installRelayCli() {
        let result = model.installRelayCli()
        showRelayCliInstallResult(result)
        refreshStatusItem()
    }
#endif

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
        button.image = model.status.statusImage(appearance: button.effectiveAppearance, playbackActive: nativePlayback.isPlaying)
    }

    private func showMenu() {
        let menu = NSMenu()

        menu.addItem(menuItem("Play Next", action: #selector(linePlayNext), enabled: model.status.queued > 0))
        if model.status.mode == "live" {
            menu.addItem(menuItem("Stop Live", action: #selector(focus), enabled: true))
        } else {
            menu.addItem(menuItem("Start Live", action: #selector(live), enabled: !model.status.muted))
        }
        menu.addItem(.separator())
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
            commandPaletteWindowController = CommandPaletteWindowController(commandsProvider: commandPaletteCommandsProvider)
        }

        commandPaletteWindowController?.show(commands: commands, initialQuery: initialQuery)
    }

#if !APP_STORE
    private func showRelayCliInstallResult(_ result: RelayCliInstallResult) {
        let alert = NSAlert()
        alert.messageText = result.title
        alert.informativeText = result.detail
        alert.alertStyle = result.succeeded ? .informational : .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
#endif

    private func menuItem(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func commandPaletteCommands() -> [CommandPaletteCommand] {
        var commands: [CommandPaletteCommand] = [
            CommandPaletteCommand(title: "Play Next", subtitle: model.status.queued > 0 ? "Release the next queued relay" : "No queued messages", aliases: ["play", "next"]) { [weak self] in
                guard let self, self.model.status.queued > 0 else {
                    return
                }
                self.model.ready()
                self.nativePlayback.playNext()
                self.refreshStatusItem()
                self.schedulePlaybackRefresh()
            },
        ]

        commands.append(contentsOf: model.status.menuLines.compactMap { line in
            let children = commandPaletteCommands(for: line)

            guard !children.isEmpty else {
                return nil
            }

            return CommandPaletteCommand(title: line.line, subtitle: "\(line.queued) queued", aliases: ["line", line.line], children: children, matchesChildren: false)
        })

        if model.status.mode == "live" {
            commands.append(CommandPaletteCommand(title: "Stop Live", subtitle: "Return to quiet focus mode", aliases: ["live", "focus", "stop"]) { [weak self] in
                self?.model.focus()
                self?.refreshStatusItem()
            })
        } else {
            commands.append(CommandPaletteCommand(title: "Start Live", subtitle: "Play new relays automatically by line", aliases: ["live", "continuous"]) { [weak self] in
                self?.model.live()
                self?.nativePlayback.playNext()
                self?.refreshStatusItem()
                self?.schedulePlaybackRefresh()
            })
        }

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

        commands.append(contentsOf: [
            CommandPaletteCommand(title: "Open Settings", subtitle: "Configure TSRS", restoresPreviousFocus: false) { [weak self] in
                self?.showSettingsWindow()
            },
            CommandPaletteCommand(title: "Quit", subtitle: "Command-Q", aliases: ["exit"], restoresPreviousFocus: false) {
                NSApplication.shared.terminate(nil)
            },
        ])

        if model.status.mode != "focus" {
            commands.append(CommandPaletteCommand(title: "Focus", subtitle: "Return to quiet focus mode") { [weak self] in
                self?.model.focus()
                self?.refreshStatusItem()
            })
        }

        return commands
    }

    private func commandPaletteCommands(for line: LineSummary) -> [CommandPaletteCommand] {
        let messages = model.recentMessages(line: line.line)
        if !messages.isEmpty {
            return messages.map { message in
                CommandPaletteCommand(
                    title: message.compactTitle,
                    subtitle: message.expandedSubtitle,
                    aliases: [message.displayStatus, message.localTime],
                    restoresPreviousFocus: true,
                    copyText: message.message,
                    lineMessage: message
                ) { [weak self] in
                    guard let self else {
                        return
                    }

                    switch message.status {
                    case "queued":
                        self.model.setActiveLine(message.line)
                        self.nativePlayback.playQueuedMessage(line: message.line, id: message.id)
                    default:
                        self.nativePlayback.replayDeliveredMessage(message.message)
                    }
                    self.refreshStatusItem()
                    self.schedulePlaybackRefresh()
                }
            }
        }

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
            commands.append(CommandPaletteCommand(title: "Reveal Source", subtitle: "Open latest source context", aliases: ["source", "reveal", line.line], restoresPreviousFocus: false) { [weak self] in
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

            if self.model.status.speaking == 0 && (self.model.status.mode != "live" || self.model.status.queued == 0) {
                timer.invalidate()
            }
        }
    }

    private func registerGlobalHotKeys() {
        unregisterGlobalHotKeys()
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var eventHandler = EventHandlerRef?.none
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
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
                default:
                    break
                }
            }

            return noErr
        }, 1, [eventSpec], nil, &eventHandler)
        if handlerStatus != noErr {
            NSLog("TSRS failed to install global hotkey handler: \(handlerStatus)")
            return
        }
        commandPaletteHotKeyEventHandler = eventHandler

        let shortcut = model.loadSettings().commandPaletteShortcut
        let registration = GlobalHotKeyRegistrationPlan.commandPalette(shortcut: shortcut)
        commandPaletteHotKey = registerHotKey(keyCode: registration.keyCode, modifiers: registration.modifiers, id: registration.id, label: registration.label)
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
        if let commandPaletteHotKey {
            UnregisterEventHotKey(commandPaletteHotKey)
            self.commandPaletteHotKey = nil
        }

        if let commandPaletteHotKeyEventHandler {
            RemoveEventHandler(commandPaletteHotKeyEventHandler)
            self.commandPaletteHotKeyEventHandler = nil
        }
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { code, character in
            (code << 8) + OSType(character)
        }
    }
}


struct KeyboardShortcut: Equatable {
    let identifier: String
    let displayName: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let defaultCommandPalette = KeyboardShortcut(
        identifier: "control-option-command-space",
        displayName: "Control + Option + Command + Space",
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | optionKey | controlKey)
    )

    private static let keyNamesByCode: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    init(identifier: String?, fallback: KeyboardShortcut = .defaultCommandPalette) {
        guard
            let identifier,
            let shortcut = Self.shortcut(identifier: identifier),
            shortcut.identifier != "control-option-command-v"
        else {
            self = fallback
            return
        }

        self = shortcut
    }

    static func recording(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> ShortcutValidationResult {
        let carbonModifiers = carbonModifiers(from: modifierFlags)
        guard carbonModifiers != 0 else {
            return .invalid("Press a shortcut with modifier keys.")
        }
        guard (carbonModifiers & UInt32(cmdKey)) != 0 else {
            return .invalid("Include Command so normal typing is not captured.")
        }
        guard (carbonModifiers & UInt32(optionKey | controlKey | shiftKey)) != 0 else {
            return .invalid("Include Control, Option, or Shift with Command.")
        }
        guard let shortcut = shortcut(keyCode: keyCode, modifiers: carbonModifiers) else {
            return .invalid("That key is not supported for a global shortcut.")
        }
        guard !isReserved(shortcut) else {
            return .invalid("Control + Option + Command + V is reserved and is not registered by TSRS.")
        }
        guard !isSystemReserved(shortcut) else {
            return .invalid("\(shortcut.displayName) is reserved by macOS or TSRS.")
        }
        return .valid(shortcut)
    }

    private static func shortcut(identifier: String) -> KeyboardShortcut? {
        let parts = identifier.split(separator: "-").map(String.init)
        guard let keyPart = parts.last else {
            return nil
        }
        let modifierParts = Set(parts.dropLast())
        var modifiers: UInt32 = 0
        if modifierParts.contains("control") { modifiers |= UInt32(controlKey) }
        if modifierParts.contains("option") { modifiers |= UInt32(optionKey) }
        if modifierParts.contains("shift") { modifiers |= UInt32(shiftKey) }
        if modifierParts.contains("command") { modifiers |= UInt32(cmdKey) }
        guard modifierParts.count == parts.count - 1 else {
            return nil
        }
        guard let keyCode = keyNamesByCode.first(where: { $0.value.lowercased() == keyPart })?.key else {
            return nil
        }
        guard let shortcut = shortcut(keyCode: keyCode, modifiers: modifiers), !isReserved(shortcut) else {
            return nil
        }
        return shortcut
    }

    private static func shortcut(keyCode: UInt32, modifiers: UInt32) -> KeyboardShortcut? {
        guard let keyName = keyNamesByCode[keyCode] else {
            return nil
        }
        let normalizedModifiers = modifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let modifierNames = modifierDisplayNames(modifiers: normalizedModifiers)
        guard !modifierNames.isEmpty else {
            return nil
        }
        let identifierParts = modifierNames.map { $0.lowercased() } + [keyName.lowercased()]
        return KeyboardShortcut(
            identifier: identifierParts.joined(separator: "-"),
            displayName: (modifierNames + [keyName]).joined(separator: " + "),
            keyCode: keyCode,
            modifiers: normalizedModifiers
        )
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func modifierDisplayNames(modifiers: UInt32) -> [String] {
        var names: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { names.append("Control") }
        if (modifiers & UInt32(optionKey)) != 0 { names.append("Option") }
        if (modifiers & UInt32(shiftKey)) != 0 { names.append("Shift") }
        if (modifiers & UInt32(cmdKey)) != 0 { names.append("Command") }
        return names
    }

    private static func isSystemReserved(_ shortcut: KeyboardShortcut) -> Bool {
        shortcut.identifier == "command-space" || shortcut.identifier == "control-command-space"
    }

    private static func isReserved(_ shortcut: KeyboardShortcut) -> Bool {
        shortcut.identifier == "control-option-command-v"
    }

    private init(identifier: String, displayName: String, keyCode: UInt32, modifiers: UInt32) {
        self.identifier = identifier
        self.displayName = displayName
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

enum ShortcutValidationResult: Equatable {
    case valid(KeyboardShortcut)
    case invalid(String)
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardShortcut = .defaultCommandPalette {
        didSet {
            if !isRecording {
                title = shortcut.displayName
            }
        }
    }
    var onShortcut: ((ShortcutValidationResult) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var isRecording = false
    private var keyMonitor: Any?

    init() {
        super.init(frame: .zero)
        title = KeyboardShortcut.defaultCommandPalette.displayName
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    @objc private func startRecording() {
        guard !isRecording else {
            return
        }
        isRecording = true
        onRecordingChanged?(true)
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
        installKeyMonitor()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        record(event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording(resetTitle: true)
        }
        return super.resignFirstResponder()
    }

    deinit {
        removeKeyMonitor()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else {
                return event
            }
            self.record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let result = KeyboardShortcut.recording(keyCode: UInt32(event.keyCode), modifierFlags: event.modifierFlags)
        stopRecording(resetTitle: false)
        onShortcut?(result)
    }

    private func stopRecording(resetTitle: Bool) {
        guard isRecording else {
            return
        }
        isRecording = false
        removeKeyMonitor()
        onRecordingChanged?(false)
        if resetTitle {
            title = shortcut.displayName
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

final class SettingsWindow: NSWindow {
    var onMoveSection: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var onQuit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            onMoveSection?(-1)
        case kVK_DownArrow:
            onMoveSection?(1)
        case kVK_Escape:
            onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
            onQuit?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsKeyboardFocusView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

struct GlobalHotKeyRegistrationPlan: Equatable {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static func commandPalette(shortcut: KeyboardShortcut) -> GlobalHotKeyRegistrationPlan {
        GlobalHotKeyRegistrationPlan(id: 1, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, label: shortcut.displayName)
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: MenuBarModel
    private let onInstallRelayCli: () -> Void
    private let onShortcutRecordingChanged: (Bool) -> Void
    private let onSave: () -> Void
    private let setupIntroView = NSTextField(labelWithString: "")
    private let cliStatusView = NSTextField(labelWithString: "")
    private let setupInstallCliButton = NSButton(title: "Install relay CLI to /usr/local/bin", target: nil, action: nil)
    private let copyBundledCliPathButton = NSButton(title: "Copy bundled CLI path", target: nil, action: nil)
    private let combinerTextView = NSTextView()
    private let voicePopUpButton = NSPopUpButton()
    private let voicePreviewButton = NSButton(title: "Preview", target: nil, action: nil)
    private let setupShortcutRecorderButton = ShortcutRecorderButton()
    private let setupShortcutStatusView = NSTextField(labelWithString: "")
    private let openAtLoginCheckbox = NSButton(checkboxWithTitle: "Open Tri-State Relay Service at login", target: nil, action: nil)
    private let openAtLoginStatusView = NSTextField(labelWithString: "")
    private var currentShortcut = KeyboardShortcut.defaultCommandPalette
    private let voicePreviewSynthesizer = AVSpeechSynthesizer()
    private let settingsTabView = NSTabView()
    private let cliSectionButton = NSButton(title: "Setup", target: nil, action: nil)
    private let voiceSectionButton = NSButton(title: "Voice", target: nil, action: nil)
    private let secondarySectionButton = NSButton(title: settingsSecondarySectionTitle, target: nil, action: nil)
    private let cliSectionRow = SidebarRowView()
    private let voiceSectionRow = SidebarRowView()
    private let secondarySectionRow = SidebarRowView()
    private let cliIconView = NSImageView(image: sidebarIcon(systemName: "terminal"))
    private let voiceIconView = NSImageView(image: sidebarIcon(systemName: "speaker.wave.2"))
    private let secondaryIconView = NSImageView(image: sidebarIcon(systemName: secondarySidebarIconName))
    private let versionLabel = NSTextField(labelWithString: "Version \(appVersion)")
    private let voiceOptions = availableSpeechVoiceOptions()
    private let keyboardNavigationFocusView = SettingsKeyboardFocusView(frame: .zero)

    init(
        model: MenuBarModel,
        onInstallRelayCli: @escaping () -> Void,
        onShortcutRecordingChanged: @escaping (Bool) -> Void,
        onSave: @escaping () -> Void
    ) {
        self.model = model
        self.onInstallRelayCli = onInstallRelayCli
        self.onShortcutRecordingChanged = onShortcutRecordingChanged
        self.onSave = onSave

        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        configureSidebarRow(cliSectionRow, button: cliSectionButton, iconView: cliIconView, selected: true)
        configureSidebarRow(voiceSectionRow, button: voiceSectionButton, iconView: voiceIconView, selected: false)
        configureSidebarRow(secondarySectionRow, button: secondarySectionButton, iconView: secondaryIconView, selected: false)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        settingsTabView.translatesAutoresizingMaskIntoConstraints = false
        settingsTabView.tabViewType = .noTabsNoBorder
        settingsTabView.addTabViewItem(NSTabViewItem(identifier: "Setup"))
        settingsTabView.addTabViewItem(NSTabViewItem(identifier: "Voice"))
#if APP_STORE
        settingsTabView.addTabViewItem(Self.readOnlyTabItem(label: "App Store Profile", message: "External combiner command templates are unavailable in the App Store-safe profile. Relay playback uses Apple speech APIs."))
#else
        settingsTabView.addTabViewItem(Self.tabItem(label: "Inactive Combiner", textView: combinerTextView))
#endif

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 430))
        keyboardNavigationFocusView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)
        sidebar.addSubview(cliSectionRow)
        sidebar.addSubview(voiceSectionRow)
        sidebar.addSubview(secondarySectionRow)
        sidebar.addSubview(versionLabel)
        content.addSubview(settingsTabView)
        content.addSubview(keyboardNavigationFocusView)

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tri-State Relay Service Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 560, height: 400)
        window.contentView = content
        window.center()

        super.init(window: window)
        window.delegate = self
        window.onMoveSection = { [weak self] offset in
            self?.selectAdjacentSection(offset)
        }
        window.onDismiss = { [weak self] in
            self?.close()
        }
        window.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        configureSetupIntroView()
        configureCliStatusView()
        settingsTabView.tabViewItem(at: 0).label = "Setup"
        settingsTabView.tabViewItem(at: 0).view = cliTabView()
        settingsTabView.tabViewItem(at: 1).label = "Voice"
        settingsTabView.tabViewItem(at: 1).view = voiceTabView()
        cliSectionButton.target = self
        cliSectionButton.action = #selector(selectCliSection)
        voiceSectionButton.target = self
        voiceSectionButton.action = #selector(selectVoiceSection)
        secondarySectionButton.target = self
        secondarySectionButton.action = #selector(selectSecondarySection)
        voicePopUpButton.target = self
        voicePopUpButton.action = #selector(selectVoice(_:))
        voicePreviewButton.target = self
        voicePreviewButton.action = #selector(previewSelectedVoice(_:))
        setupShortcutRecorderButton.onShortcut = { [weak self] result in
            self?.recordShortcut(result)
        }
        setupShortcutRecorderButton.onRecordingChanged = { [weak self] isRecording in
            self?.onShortcutRecordingChanged(isRecording)
        }
        setupInstallCliButton.target = self
        setupInstallCliButton.action = #selector(installRelayCliFromSetup)
        copyBundledCliPathButton.target = self
        copyBundledCliPathButton.action = #selector(copyBundledRelayCliPath)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 160),
            cliSectionRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            cliSectionRow.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            cliSectionRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 32),
            cliSectionRow.heightAnchor.constraint(equalToConstant: 38),
            voiceSectionRow.leadingAnchor.constraint(equalTo: cliSectionRow.leadingAnchor),
            voiceSectionRow.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            voiceSectionRow.topAnchor.constraint(equalTo: cliSectionRow.bottomAnchor, constant: 6),
            voiceSectionRow.heightAnchor.constraint(equalTo: cliSectionRow.heightAnchor),
            secondarySectionRow.leadingAnchor.constraint(equalTo: voiceSectionRow.leadingAnchor),
            secondarySectionRow.trailingAnchor.constraint(equalTo: voiceSectionRow.trailingAnchor),
            secondarySectionRow.topAnchor.constraint(equalTo: voiceSectionRow.bottomAnchor, constant: 6),
            secondarySectionRow.heightAnchor.constraint(equalTo: voiceSectionRow.heightAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            versionLabel.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            versionLabel.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16),
            settingsTabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            settingsTabView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 28),
            settingsTabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            settingsTabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
            keyboardNavigationFocusView.widthAnchor.constraint(equalToConstant: 0),
            keyboardNavigationFocusView.heightAnchor.constraint(equalToConstant: 0),
            keyboardNavigationFocusView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            keyboardNavigationFocusView.topAnchor.constraint(equalTo: content.topAnchor),
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

    @objc private func selectCliSection() {
        settingsTabView.selectTabViewItem(at: 0)
        updateSidebarSelection(selectedIndex: 0)
    }

    @objc private func selectVoiceSection() {
        settingsTabView.selectTabViewItem(at: 1)
        updateSidebarSelection(selectedIndex: 1)
    }

    @objc private func selectSecondarySection() {
        settingsTabView.selectTabViewItem(at: 2)
        updateSidebarSelection(selectedIndex: 2)
    }

    private func selectAdjacentSection(_ offset: Int) {
        let currentIndex = settingsTabView.indexOfTabViewItem(settingsTabView.selectedTabViewItem ?? settingsTabView.tabViewItem(at: 0))
        let maxIndex = settingsTabView.numberOfTabViewItems - 1
        let nextIndex = min(max(currentIndex + offset, 0), maxIndex)
        settingsTabView.selectTabViewItem(at: nextIndex)
        updateSidebarSelection(selectedIndex: nextIndex)
        window?.makeFirstResponder(keyboardNavigationFocusView)
    }

    @objc private func selectVoice(_ sender: Any?) {
        model.saveVoiceSetting(voiceIdentifier: selectedVoiceIdentifier())
        model.completeFirstStartSetup()
        updateSetupIntroVisibility()
        onSave()
    }

    @objc private func installRelayCliFromSetup() {
        onInstallRelayCli()
        reloadCliStatus()
    }

    @objc private func copyBundledRelayCliPath() {
#if !APP_STORE
        model.copyRelayCliBundledPath()
        reloadCliStatus()
#endif
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
        reloadShortcutRecorder(selectedShortcut: settings.commandPaletteShortcut)
        reloadOpenAtLogin()
        updateSetupIntroVisibility()
        reloadCliStatus()
    }

    private func saveCombinerIfNeeded() {
#if !APP_STORE
        model.saveSettings(
            inactiveLineCombinerCommand: combinerTextView.string,
            voiceIdentifier: selectedVoiceIdentifier(),
            commandPaletteShortcut: currentShortcut
        )
        model.completeFirstStartSetup()
        updateSetupIntroVisibility()
        onSave()
#endif
    }

    private func configureSetupIntroView() {
        setupIntroView.stringValue = ""
        setupIntroView.textColor = .secondaryLabelColor
        setupIntroView.font = NSFont.systemFont(ofSize: 12)
        setupIntroView.lineBreakMode = .byWordWrapping
        setupIntroView.maximumNumberOfLines = 0
    }

    private func configureCliStatusView() {
        cliStatusView.textColor = .secondaryLabelColor
        cliStatusView.font = NSFont.systemFont(ofSize: 12)
        cliStatusView.lineBreakMode = .byWordWrapping
        cliStatusView.maximumNumberOfLines = 0
        setupShortcutStatusView.textColor = .secondaryLabelColor
        setupShortcutStatusView.font = NSFont.systemFont(ofSize: 12)
        setupShortcutStatusView.lineBreakMode = .byWordWrapping
        setupShortcutStatusView.maximumNumberOfLines = 0
        openAtLoginStatusView.textColor = .secondaryLabelColor
        openAtLoginStatusView.font = NSFont.systemFont(ofSize: 12)
        openAtLoginStatusView.lineBreakMode = .byWordWrapping
        openAtLoginStatusView.maximumNumberOfLines = 0
    }

    private func updateSetupIntroVisibility() {
        setupIntroView.isHidden = true
    }

#if !APP_STORE
    private func reloadCliStatus() {
        let status = model.relayCliInstallStatus()
        cliStatusView.stringValue = relayCliSettingsMessage(status)
        setupInstallCliButton.title = status.status == "stale" ? "Update relay CLI at \(status.targetPath)" : "Install relay CLI to \(status.targetPath)"
    }
#else
    private func reloadCliStatus() {}
#endif

    private func reloadOpenAtLogin() {
        let enabled = model.openAtLoginEnabled()
        openAtLoginCheckbox.state = enabled ? .on : .off
        openAtLoginStatusView.stringValue = enabled
            ? "TSRS will open automatically when you log in."
            : "Leave this off if you prefer to start TSRS manually."
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

        let combinerLabel = NSTextField(labelWithString: "Inactive-line combiner command")
        combinerLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let combinerNote = NSTextField(labelWithString: "Optional command used to combine inactive-line updates. Leave commented for latest-only behavior.")
        combinerNote.textColor = .secondaryLabelColor
        combinerNote.font = NSFont.systemFont(ofSize: 12)
        combinerNote.lineBreakMode = .byWordWrapping
        combinerNote.maximumNumberOfLines = 0

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        let stack = NSStackView(views: [title, combinerLabel, combinerNote, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(18, after: title)
        stack.setCustomSpacing(9, after: combinerNote)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            combinerNote.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
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

    private func cliTabView() -> NSView {
        let title = NSTextField(labelWithString: "Setup")
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Get the local CLI and keyboard shortcut ready before agents start sending updates.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0

        let cliLabel = NSTextField(labelWithString: "1. Install the CLI")
        cliLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let buttonRow = NSStackView(views: [setupInstallCliButton, copyBundledCliPathButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let shortcutLabel = NSTextField(labelWithString: "2. Record the shortcut")
        shortcutLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let shortcutNote = NSTextField(labelWithString: "Click the button, then press a valid key combination.")
        shortcutNote.textColor = .secondaryLabelColor
        shortcutNote.font = NSFont.systemFont(ofSize: 12)
        shortcutNote.lineBreakMode = .byWordWrapping
        shortcutNote.maximumNumberOfLines = 0

        let openAtLoginLabel = NSTextField(labelWithString: "3. Open at Login")
        openAtLoginLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        openAtLoginCheckbox.target = self
        openAtLoginCheckbox.action = #selector(toggleOpenAtLogin(_:))

        let cliSection = NSStackView(views: [cliLabel, cliStatusView, buttonRow])
        cliSection.orientation = .vertical
        cliSection.alignment = .leading
        cliSection.spacing = 7
        cliSection.translatesAutoresizingMaskIntoConstraints = false

        let shortcutSection = NSStackView(views: [shortcutLabel, shortcutNote, setupShortcutRecorderButton, setupShortcutStatusView])
        shortcutSection.orientation = .vertical
        shortcutSection.alignment = .leading
        shortcutSection.spacing = 7
        shortcutSection.translatesAutoresizingMaskIntoConstraints = false

        let openAtLoginSection = NSStackView(views: [openAtLoginLabel, openAtLoginStatusView, openAtLoginCheckbox])
        openAtLoginSection.orientation = .vertical
        openAtLoginSection.alignment = .leading
        openAtLoginSection.spacing = 7
        openAtLoginSection.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, subtitle, cliSection, shortcutSection, openAtLoginSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        cliStatusView.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        setupShortcutRecorderButton.widthAnchor.constraint(equalToConstant: 460).isActive = true
        setupShortcutStatusView.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        shortcutNote.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        openAtLoginStatusView.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        cliSection.setCustomSpacing(9, after: cliStatusView)
        shortcutSection.setCustomSpacing(9, after: shortcutNote)
        openAtLoginSection.setCustomSpacing(9, after: openAtLoginStatusView)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(18, after: cliSection)
        stack.setCustomSpacing(18, after: shortcutSection)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 270))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])

        return container
    }

    @objc private func toggleOpenAtLogin(_ sender: NSButton) {
        let enabled = sender.state == .on

        do {
            try model.setOpenAtLoginEnabled(enabled)
            model.completeFirstStartSetup()
            updateSetupIntroVisibility()
            reloadOpenAtLogin()
            onSave()
        } catch {
            sender.state = model.openAtLoginEnabled() ? .on : .off
            openAtLoginStatusView.stringValue = "Could not update Open at Login: \(error.localizedDescription)"
        }
    }

    private func voiceTabView() -> NSView {
        let title = NSTextField(labelWithString: "Voice")
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        let voiceLabel = NSTextField(labelWithString: "Speech voice")
        voiceLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        let voiceNote = NSTextField(labelWithString: "Choose the voice TSRS uses when it speaks a relay. Use Preview to hear a sample.")
        voiceNote.textColor = .secondaryLabelColor
        voiceNote.font = NSFont.systemFont(ofSize: 12)
        voiceNote.lineBreakMode = .byWordWrapping
        voiceNote.maximumNumberOfLines = 0

        let voiceRow = NSStackView(views: [voicePopUpButton, voicePreviewButton])
        voiceRow.orientation = .horizontal
        voiceRow.alignment = .centerY
        voiceRow.spacing = 8

        let stack = NSStackView(views: [title, voiceLabel, voiceNote, voiceRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        voicePopUpButton.widthAnchor.constraint(equalToConstant: 340).isActive = true
        voicePreviewButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
        voiceNote.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        stack.setCustomSpacing(18, after: title)
        stack.setCustomSpacing(9, after: voiceNote)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 180))
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])

        return container
    }

    private func reloadShortcutRecorder(selectedShortcut: KeyboardShortcut) {
        currentShortcut = selectedShortcut
        setupShortcutRecorderButton.shortcut = selectedShortcut
        setupShortcutStatusView.stringValue = ""
        setupShortcutStatusView.isHidden = true
        setupShortcutStatusView.textColor = .secondaryLabelColor
    }

    private func recordShortcut(_ result: ShortcutValidationResult) {
        switch result {
        case .valid(let shortcut):
            currentShortcut = shortcut
            setupShortcutRecorderButton.shortcut = shortcut
            setupShortcutStatusView.stringValue = "Saved shortcut: \(shortcut.displayName)"
            setupShortcutStatusView.isHidden = false
            setupShortcutStatusView.textColor = .secondaryLabelColor
            model.saveCommandPaletteShortcut(shortcut)
            model.completeFirstStartSetup()
            updateSetupIntroVisibility()
            onSave()
        case .invalid(let message):
            setupShortcutRecorderButton.shortcut = currentShortcut
            setupShortcutStatusView.stringValue = message
            setupShortcutStatusView.isHidden = false
            setupShortcutStatusView.textColor = .systemRed
        }
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

    private func updateSidebarSelection(selectedIndex: Int) {
        let cliSelected = selectedIndex == 0
        let voiceSelected = selectedIndex == 1
        let secondarySelected = selectedIndex == 2
        configureSidebarButton(cliSectionButton, selected: cliSelected)
        configureSidebarButton(voiceSectionButton, selected: voiceSelected)
        configureSidebarButton(secondarySectionButton, selected: secondarySelected)
        cliIconView.contentTintColor = cliSelected ? .selectedMenuItemTextColor : .secondaryLabelColor
        voiceIconView.contentTintColor = voiceSelected ? .selectedMenuItemTextColor : .secondaryLabelColor
        secondaryIconView.contentTintColor = secondarySelected ? .selectedMenuItemTextColor : .secondaryLabelColor
        cliSectionRow.selected = cliSelected
        voiceSectionRow.selected = voiceSelected
        secondarySectionRow.selected = secondarySelected
    }
}

struct CommandPaletteCommand {
    let title: String
    let subtitle: String
    let aliases: [String]
    let children: [CommandPaletteCommand]
    let restoresPreviousFocus: Bool
    let copyText: String?
    let lineMessage: LineMessage?
    let matchesChildren: Bool
    let action: () -> Void

    init(title: String, subtitle: String, aliases: [String] = [], children: [CommandPaletteCommand] = [], restoresPreviousFocus: Bool = true, copyText: String? = nil, lineMessage: LineMessage? = nil, matchesChildren: Bool = true, action: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.children = children
        self.restoresPreviousFocus = restoresPreviousFocus
        self.copyText = copyText
        self.lineMessage = lineMessage
        self.matchesChildren = matchesChildren
        self.action = action
    }

    func matches(_ query: String) -> Bool {
        matchScore(query) != nil
    }

    func matchScore(_ query: String) -> Int? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.isEmpty {
            return 0
        }

        if title.lowercased().contains(normalized) {
            return 100
        }

        if aliases.contains(where: { $0.lowercased().contains(normalized) }) {
            return 90
        }

        if subtitle.lowercased().contains(normalized) {
            return 80
        }

        if matchesChildren && children.contains(where: { $0.matches(normalized) }) {
            return 10
        }

        return nil
    }
}

final class CommandPaletteWindowController: NSWindowController, NSTextFieldDelegate {
    private static let panelWidth: CGFloat = 560
    private static let outerPadding: CGFloat = 12
    private static let contentInset: CGFloat = 18
    private static let rowOuterPadding: CGFloat = 6
    private static let searchHeight: CGFloat = 34
    private static let searchToDividerSpacing: CGFloat = 2
    private static let dividerToResultsSpacing: CGFloat = 8
    private static let rowHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 4
    private static let maxVisibleRows = 5
    private let searchField = CommandPaletteSearchField()
    private let headerDivider = NSBox()
    private let resultsStack = NSStackView()
    private let commandsProvider: () -> [CommandPaletteCommand]
    private var allCommands: [CommandPaletteCommand] = []
    private var rootCommands: [CommandPaletteCommand] = []
    private var filteredCommands: [CommandPaletteCommand] = []
    private var selectedIndex = 0
    private var previousApplication: NSRunningApplication?
    private var navigationStack: [(title: String, commands: [CommandPaletteCommand])] = []
    private var refreshTimer: Timer?

    init(commandsProvider: @escaping () -> [CommandPaletteCommand]) {
        self.commandsProvider = commandsProvider
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 120),
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
        panel.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        super.init(window: panel)
        panel.onCopy = { [weak self] in
            self?.copySelectedCommandText() ?? false
        }
        panel.onScroll = { [weak self] delta in
            self?.moveSelection(delta) ?? false
        }
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
        startRefreshing()
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    private func buildContent() {
        guard let window else {
            return
        }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        searchField.placeholderString = "Search Tri-State Relay Service actions..."
        searchField.delegate = self

        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.boxType = .separator

        resultsStack.orientation = .vertical
        resultsStack.alignment = .centerX
        resultsStack.spacing = Self.rowSpacing
        resultsStack.translatesAutoresizingMaskIntoConstraints = false

        let content = RoundedCommandPaletteBackgroundView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active
        content.onScroll = { [weak self] delta in
            self?.moveSelection(delta) ?? false
        }
        content.addSubview(searchField)
        content.addSubview(headerDivider)
        content.addSubview(resultsStack)
        window.contentView = content

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.outerPadding),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.contentInset),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.contentInset),
            searchField.heightAnchor.constraint(equalToConstant: Self.searchHeight),
            headerDivider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Self.searchToDividerSpacing),
            headerDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            resultsStack.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: Self.dividerToResultsSpacing),
            resultsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.rowOuterPadding),
            resultsStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.rowOuterPadding),
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

        if selector == #selector(NSText.copy(_:)), copySelectedCommandText() {
            return true
        }

        if selector == #selector(NSResponder.deleteBackward(_:)), searchField.stringValue.isEmpty, !navigationStack.isEmpty {
            navigateBack()
            return true
        }

        return false
    }

    private func filterCommands() {
        filteredCommands = allCommands
            .compactMap { command -> (command: CommandPaletteCommand, score: Int)? in
                guard let score = command.matchScore(searchField.stringValue) else {
                    return nil
                }

                return (command, score)
            }
            .sorted { first, second in
                first.score > second.score
            }
            .map(\.command)

        if selectedIndex >= filteredCommands.count {
            selectedIndex = max(0, filteredCommands.count - 1)
        }

        renderResults()
    }

    private func startRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshCommands()
        }
    }

    private func refreshCommands() {
        guard navigationStack.isEmpty else {
            return
        }

        allCommands = commandsProvider()
        rootCommands = allCommands
        filterCommands()
    }

    private func moveSelection(_ delta: Int) -> Bool {
        guard !filteredCommands.isEmpty else {
            return false
        }

        let nextIndex = min(max(selectedIndex + delta, 0), filteredCommands.count - 1)
        guard nextIndex != selectedIndex else {
            return false
        }

        selectedIndex = nextIndex
        renderResults()
        return true
    }

    private func executeSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else {
            return
        }

        let command = filteredCommands[selectedIndex]
        if command.children.isEmpty {
            close()
            command.action()
            if command.restoresPreviousFocus {
                restorePreviousApplication()
            } else {
                previousApplication = nil
            }
        } else {
            navigationStack.append((title: command.title, commands: allCommands))
            allCommands = command.children
            searchField.stringValue = ""
            selectedIndex = 0
            filterCommands()
        }
    }

    private func copySelectedCommandText() -> Bool {
        guard filteredCommands.indices.contains(selectedIndex), let copyText = filteredCommands[selectedIndex].copyText else {
            return false
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
        close()
        restorePreviousApplication()
        return true
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
            let emptyTitle = navigationStack.isEmpty ? "No matches." : "No messages on this line yet."
            let emptySubtitle = navigationStack.isEmpty ? "Try another query" : ""
            resultsStack.addArrangedSubview(resultRow(title: emptyTitle, subtitle: emptySubtitle, selected: false, height: Self.rowHeight))
            resizeWindow(rowCount: 1)
            return
        }

        let visibleItems = visibleCommands()
        for item in visibleItems {
            resultsStack.addArrangedSubview(resultRow(command: item.command, selected: item.index == selectedIndex, onHover: { [weak self] in
                guard let self, self.filteredCommands.indices.contains(item.index), self.selectedIndex != item.index else {
                    return
                }
                self.selectedIndex = item.index
                self.renderResults()
            }) { [weak self] in
                self?.selectedIndex = item.index
                self?.executeSelected()
            })
        }
        resizeWindow(rowHeights: resultsStack.arrangedSubviews.map(\.fittingSize.height))
    }

    private func visibleCommands(limit: Int = 5) -> [(index: Int, command: CommandPaletteCommand)] {
        guard !filteredCommands.isEmpty else {
            return []
        }

        let maxStartIndex = max(0, filteredCommands.count - limit)
        let startIndex = min(max(selectedIndex - limit + 1, 0), maxStartIndex)
        let endIndex = min(startIndex + limit, filteredCommands.count)
        return (startIndex..<endIndex).map { index in
            (index: index, command: filteredCommands[index])
        }
    }

    private func resizeWindow(rowCount: Int) {
        resizeWindow(rowHeights: Array(repeating: Self.rowHeight, count: rowCount))
    }

    private func resizeWindow(rowHeights: [CGFloat]) {
        guard let window else {
            return
        }

        let rowsHeight = rowHeights.reduce(0, +)
        let rowGapsHeight = CGFloat(max(0, rowHeights.count - 1)) * Self.rowSpacing
        let height = Self.outerPadding
            + Self.searchHeight
            + Self.searchToDividerSpacing
            + 1
            + Self.dividerToResultsSpacing
            + rowsHeight
            + rowGapsHeight
            + Self.outerPadding
        var frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = NSSize(width: Self.panelWidth, height: height)
        frame.origin = NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        window.setFrame(frame, display: true)
    }

    private func rowHeight(command: CommandPaletteCommand, selected: Bool) -> CGFloat {
        command.lineMessage != nil && selected ? 0 : Self.rowHeight
    }

    private func resultRow(command: CommandPaletteCommand, selected: Bool, onHover: (() -> Void)? = nil, action: (() -> Void)? = nil) -> NSView {
        resultRow(title: command.lineMessage.map { selected ? $0.message : $0.previewTitle } ?? command.title, subtitle: command.lineMessage.map { selected ? $0.expandedSubtitle : $0.compactSubtitle } ?? command.subtitle, selected: selected, height: rowHeight(command: command, selected: selected), onHover: onHover, action: action)
    }

    private func resultRow(title: String, subtitle: String, selected: Bool, height: CGFloat, onHover: (() -> Void)? = nil, action: (() -> Void)? = nil) -> NSView {
        let row = PaletteResultRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.selected = selected
        row.action = action
        row.onHover = onHover
        row.onScroll = { [weak self] delta in
            self?.moveSelection(delta) ?? false
        }

        let displayTitle = subtitle == "submenu" ? "\(title) ›" : title
        let titleField = NSTextField(labelWithString: displayTitle)
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = selected ? .byWordWrapping : .byTruncatingTail
        titleField.maximumNumberOfLines = selected ? 4 : 1
        titleField.preferredMaxLayoutWidth = Self.panelWidth - (Self.contentInset * 2)
        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.maximumNumberOfLines = selected ? 2 : 1
        subtitleField.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)

        var constraints = [
            row.widthAnchor.constraint(equalToConstant: Self.panelWidth - (Self.rowOuterPadding * 2)),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.contentInset - Self.rowOuterPadding),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -(Self.contentInset - Self.rowOuterPadding)),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: selected ? -8 : 0),
        ]
        if selected {
            constraints.append(stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8))
        } else {
            constraints.append(row.heightAnchor.constraint(equalToConstant: height))
            constraints.append(stack.centerYAnchor.constraint(equalTo: row.centerYAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        return row
    }
}

final class CommandPaletteSearchField: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = true
        isSelectable = true
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        textColor = .labelColor
        placeholderAttributedString = NSAttributedString(
            string: "Search Tri-State Relay Service actions...",
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.systemFont(ofSize: 22, weight: .regular),
            ]
        )
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class RoundedCommandPaletteBackgroundView: NSVisualEffectView {
    var onScroll: ((Int) -> Bool)?

    override func layout() {
        super.layout()
        maskImage = roundedMaskImage(size: bounds.size, radius: 18)
    }

    private func roundedMaskImage(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: radius, yRadius: radius).fill()
        image.unlockFocus()
        return image
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY < 0 ? 1 : -1
        _ = onScroll?(delta)
    }
}

final class CommandPalettePanel: NSPanel {
    var onQuit: (() -> Void)?
    var onCopy: (() -> Bool)?
    var onScroll: ((Int) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c", onCopy?() == true {
            return true
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
            onQuit?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c", onCopy?() == true {
            return
        }

        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY < 0 ? 1 : -1
        _ = onScroll?(delta)
    }

}

final class PaletteResultRowView: NSView {
    var action: (() -> Void)?
    var onHover: (() -> Void)?
    var onScroll: ((Int) -> Bool)?
    private var trackingAreaRef: NSTrackingArea?
    var selected = false {
        didSet {
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        action?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?()
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY < 0 ? 1 : -1
        _ = onScroll?(delta)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard selected else {
            return
        }

        resolvedColor(.controlAccentColor).withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 8, yRadius: 8).fill()
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
    row.action = { [weak button] in
        guard let button, let action = button.action else {
            return
        }
        NSApp.sendAction(action, to: button.target, from: button)
    }
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
    var action: (() -> Void)?
    var selected = false {
        didSet {
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        action?()
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

private func resolvedColor(_ color: NSColor, appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
    NSAppearance.current = appearance
    defer {
        NSAppearance.current = nil
    }
    return color.usingColorSpace(.deviceRGB) ?? color
}

private func menuBarIconStrokeColor(appearance: NSAppearance) -> NSColor {
    if menuBarIsDark(appearance: appearance) {
        return .white
    }

    return .black
}

private func menuBarQueuedAccentColor(appearance: NSAppearance) -> NSColor {
    if menuBarIsDark(appearance: appearance) {
        return NSColor(calibratedRed: 1, green: 0.32, blue: 0.28, alpha: 1)
    }

    return resolvedColor(.systemRed, appearance: appearance)
}

private func menuBarLiveAccentColor(appearance: NSAppearance) -> NSColor {
    if menuBarIsDark(appearance: appearance) {
        return NSColor(calibratedRed: 0.28, green: 0.9, blue: 0.38, alpha: 1)
    }

    return resolvedColor(.systemGreen, appearance: appearance)
}

private func menuBarIsDark(appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

    var isPlaying: Bool {
        currentProcess != nil || synthesizer.isSpeaking
    }

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

        onChange()
        speak(claim)
    }

    func playQueuedMessage(line: String, id: Int) {
        guard !synthesizer.isSpeaking, currentProcess == nil else {
            return
        }

        if inputCaptureSensor.isInputCaptureActive() {
            model.refresh()
            onChange()
            return
        }

        guard let claim = model.claimQueuedMessageForNativeSpeech(line: line, id: id) else {
            model.refresh()
            onChange()
            return
        }

        currentId = claim.id
        onChange()
        speak(claim)
    }

    func replayDeliveredMessage(_ text: String) {
        model.refresh()
        guard !model.status.muted, !synthesizer.isSpeaking, currentProcess == nil else {
            model.refresh()
            onChange()
            return
        }

        if inputCaptureSensor.isInputCaptureActive() {
            model.refresh()
            onChange()
            return
        }

        onChange()
        speakReplay(text)
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
                if self.model.status.mode == "live" {
                    self.playNext()
                }
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

    private func speakReplay(_ text: String) {
#if APP_STORE
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredRelayVoice(identifier: model.loadSettings().speechVoiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1
        synthesizer.speak(utterance)
#else
        let option = speechVoiceOption(identifier: model.loadSettings().speechVoiceIdentifier)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = sayArguments(text: text, option: option)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.currentProcess = nil
                self.onChange()
            }
        }

        do {
            currentProcess = process
            try process.run()
        } catch {
            currentProcess = nil
            onChange()
        }
#endif
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard let id = currentId else {
            onChange()
            return
        }

        model.markNativeSpeechHeard(id: id)
        currentId = nil
        onChange()
        if model.status.mode == "live" {
            playNext()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard let id = currentId else {
            onChange()
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
    let isNatural: Bool

    init(identifier: String, name: String, title: String, isNatural: Bool = false) {
        self.identifier = identifier
        self.name = name
        self.title = title
        self.isNatural = isNatural
    }
}

let systemSayVoiceIdentifier = "system-say-default"
let defaultSpeechVoiceIdentifier = systemSayVoiceIdentifier
let defaultSpeechVoiceOption = SpeechVoiceOption(identifier: systemSayVoiceIdentifier, name: "System Default", title: "System Default (say)")

func availableSpeechVoiceOptions() -> [SpeechVoiceOption] {
#if APP_STORE
    return availableRelayVoices().map { voice in
        SpeechVoiceOption(identifier: voice.identifier, name: voice.name, title: speechVoiceTitle(name: voice.name, language: voice.language, isNatural: isNaturalVoice(identifier: voice.identifier, name: voice.name)), isNatural: isNaturalVoice(identifier: voice.identifier, name: voice.name))
    }
#else
    return directSpeechVoiceOptions()
#endif
}

func speechVoiceOption(identifier: String?) -> SpeechVoiceOption {
    availableSpeechVoiceOptions().first { $0.identifier == identifier } ?? defaultSpeechVoiceOption
}

func sayArguments(text: String, option: SpeechVoiceOption) -> [String] {
    if let sayVoiceName = option.sayVoiceName {
        return ["-v", sayVoiceName, text]
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

private func directSpeechVoiceOptions() -> [SpeechVoiceOption] {
    let installedOptions = NSSpeechSynthesizer.availableVoices.compactMap(saySpeechVoiceOption)
    return [defaultSpeechVoiceOption] + installedOptions.sorted(by: speechVoiceSort)
}

private func saySpeechVoiceOption(_ voice: NSSpeechSynthesizer.VoiceName) -> SpeechVoiceOption? {
    let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
    let name = (attributes[.name] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let language = (attributes[.localeIdentifier] as? String) ?? ""

    guard !name.isEmpty, language.hasPrefix("en"), !noveltySayVoiceNames.contains(name) else {
        return nil
    }

    let identifier = "say:\(name)"
    let natural = isNaturalVoice(identifier: voice.rawValue, name: name)
    return SpeechVoiceOption(identifier: identifier, name: name, title: speechVoiceTitle(name: name, language: language, isNatural: natural), isNatural: natural)
}

private func speechVoiceTitle(name: String, language: String, isNatural: Bool) -> String {
    let suffix = isNatural ? "Natural" : language
    return suffix.isEmpty ? name : "\(name) (\(suffix))"
}

private func speechVoiceSort(_ left: SpeechVoiceOption, _ right: SpeechVoiceOption) -> Bool {
    if left.isNatural != right.isNatural {
        return left.isNatural
    }

    let leftUS = left.title.contains("en_US") || left.title.contains("en-US")
    let rightUS = right.title.contains("en_US") || right.title.contains("en-US")
    if leftUS != rightUS {
        return leftUS
    }

    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
}

private func isNaturalVoice(identifier: String, name: String) -> Bool {
    let haystack = "\(identifier) \(name)".lowercased()
    return haystack.contains("premium")
        || haystack.contains("enhanced")
        || haystack.contains("siri")
        || haystack.contains("natural")
}

private extension SpeechVoiceOption {
    var sayVoiceName: String? {
        guard identifier.hasPrefix("say:") else {
            return nil
        }

        return String(identifier.dropFirst("say:".count))
    }
}

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

    func live() {
        store.setMode("live")
        refresh()
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

    func claimQueuedMessageForNativeSpeech(line: String, id: Int) -> NativeSpeechClaim? {
        store.claimQueuedMessageForNativeSpeech(line: line, id: id)
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

    func recentMessages(line: String, limit: Int = 20) -> [LineMessage] {
        store.recentMessages(line: line, limit: limit)
    }

    func needsFirstStartSetup() -> Bool {
        store.needsFirstStartSetup()
    }

    func completeFirstStartSetup() {
        store.completeFirstStartSetup()
        refresh()
    }

    func saveSettings(inactiveLineCombinerCommand: String, voiceIdentifier: String, commandPaletteShortcut: KeyboardShortcut) {
        store.saveSettings(
            inactiveLineCombinerCommand: inactiveLineCombinerCommand,
            voiceIdentifier: voiceIdentifier,
            commandPaletteShortcut: commandPaletteShortcut
        )
        refresh()
    }

    func saveVoiceSetting(voiceIdentifier: String) {
        store.saveVoiceIdentifier(voiceIdentifier)
        refresh()
    }

    func saveCommandPaletteShortcut(_ shortcut: KeyboardShortcut) {
        store.saveCommandPaletteShortcut(shortcut)
        refresh()
    }

    func openAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setOpenAtLoginEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

#if !APP_STORE
    func relayCliInstallStatus() -> RelayCliInstallStatus {
        relayCliStatusFromBundledCommand()
    }

    func copyRelayCliBundledPath() {
        copyNativeSource(relayCliInstallStatus().sourcePath)
    }

    func relayCliMenuTitle() -> String {
        switch relayCliInstallStatus().status {
        case "current":
            return "Reinstall relay CLI..."
        case "stale":
            return "Update relay CLI..."
        case "foreign":
            return "Resolve relay CLI Conflict..."
        default:
            return "Install relay CLI..."
        }
    }

    func installRelayCli() -> RelayCliInstallResult {
        let preflight = relayCliInstallStatus()

        if preflight.status == "current" {
            return RelayCliInstallResult(
                succeeded: true,
                title: "relay CLI is already installed",
                detail: "Installed at \(preflight.targetPath)."
            )
        }

        if preflight.status == "source-missing" || preflight.status == "foreign" {
            return RelayCliInstallResult(
                succeeded: false,
                title: "Could not install relay CLI",
                detail: preflight.message
            )
        }

        let command = runBundledRelay(arguments: ["install-cli"])

        if command.status != 0 {
            let privileged = installRelayCliWithAdministratorPrivileges(sourcePath: preflight.sourcePath, targetPath: preflight.targetPath)

            if !privileged.succeeded {
                return privileged
            }
        }

        let status = command.status == 0
            ? parseRelayCliInstallStatus(command.stdout)
            : relayCliInstallStatus()

        guard status.status == "current" else {
            return RelayCliInstallResult(
                succeeded: false,
                title: "Could not install relay CLI",
                detail: status.message
            )
        }

        let pathNote = status.targetDirectoryOnPath
            ? ""
            : "\n\nAdd \(deletingLastPathComponent(status.targetPath)) to PATH so agents can run `relay` without a full path."

        return RelayCliInstallResult(
            succeeded: true,
            title: "relay CLI installed",
            detail: "Installed \(status.targetPath).\(pathNote)"
        )
    }

    private func installRelayCliWithAdministratorPrivileges(sourcePath: String?, targetPath: String) -> RelayCliInstallResult {
        guard let sourcePath else {
            return RelayCliInstallResult(
                succeeded: false,
                title: "Could not install relay CLI",
                detail: "The bundled app-contents CLI could not be found. Rebuild or reinstall the app."
            )
        }

        let script = """
        on run argv
          set src to item 1 of argv
          set dst to item 2 of argv
          set dirCommand to "/usr/bin/dirname " & quoted form of dst
          set dstDir to do shell script dirCommand
          set installCommand to "/bin/mkdir -p " & quoted form of dstDir & " && if [ -L " & quoted form of dst & " ]; then echo 'Refusing to overwrite symlink: " & quoted form of dst & "' >&2; exit 73; fi && /bin/cp -f " & quoted form of src & " " & quoted form of dst & " && /bin/chmod 755 " & quoted form of dst
          do shell script installCommand with administrator privileges
        end run
        """

        let command = runAppleScript(script: script, arguments: [sourcePath, targetPath])

        guard command.status == 0 else {
            let detail = command.stderr.isEmpty ? command.stdout : command.stderr
            return RelayCliInstallResult(
                succeeded: false,
                title: "Could not install relay CLI",
                detail: detail.isEmpty ? "The administrator install was cancelled or failed." : detail
            )
        }

        let status = relayCliInstallStatus()

        guard status.status == "current" else {
            return RelayCliInstallResult(
                succeeded: false,
                title: "Could not install relay CLI",
                detail: status.message
            )
        }

        return RelayCliInstallResult(
            succeeded: true,
            title: "relay CLI installed",
            detail: "Installed \(status.targetPath)."
        )
    }

    private func relayCliStatusFromBundledCommand() -> RelayCliInstallStatus {
        let command = runBundledRelay(arguments: ["cli-status"])

        guard command.status == 0 else {
            return RelayCliInstallStatus(
                status: "source-missing",
                sourcePath: nil,
                sourceSignature: nil,
                targetPath: "/usr/local/bin/relay",
                targetDirectoryOnPath: false,
                version: "unknown",
                message: command.stderr.isEmpty ? command.stdout : command.stderr
            )
        }

        return parseRelayCliInstallStatus(command.stdout)
    }

    private func runBundledRelay(arguments: [String]) -> RelayCliCommandResult {
        guard let executableURL = Bundle.main.executableURL else {
            return RelayCliCommandResult(status: 1, stdout: "", stderr: "could not locate app executable")
        }

        let relayURL = executableURL.deletingLastPathComponent().appendingPathComponent("relay")
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = relayURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return RelayCliCommandResult(status: 1, stdout: "", stderr: error.localizedDescription)
        }

        return RelayCliCommandResult(
            status: Int(process.terminationStatus),
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func runAppleScript(script: String, arguments: [String]) -> RelayCliCommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "--"] + arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return RelayCliCommandResult(status: 1, stdout: "", stderr: error.localizedDescription)
        }

        return RelayCliCommandResult(
            status: Int(process.terminationStatus),
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
#endif

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

struct LineMessage {
    let id: Int
    let line: String
    let message: String
    let status: String
    let createdAt: String
    let updatedAt: String

    var displayStatus: String {
        status == "queued" ? "Queued" : "Delivered"
    }

    var localTime: String {
        guard let date = nativeRelayTimestampFormatter.date(from: updatedAt.isEmpty ? createdAt : updatedAt) else {
            return ""
        }
        return lineMessageTimeFormatter.string(from: date)
    }

    var previewTitle: String {
        "\(displayStatus) \(localTime)   \(truncatedMessage(limit: 64))"
    }

    var compactTitle: String {
        previewTitle
    }

    var compactSubtitle: String {
        ""
    }

    var expandedSubtitle: String {
        "\(displayStatus) \(localTime)\nEnter Replay    Command-C Copy"
    }

    private func truncatedMessage(limit: Int) -> String {
        guard message.count > limit else {
            return message
        }

        return "\(message.prefix(limit - 1))…"
    }
}

private let nativeRelayTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter
}()

private let lineMessageTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter
}()

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

        if mode == "live" {
            return "TSRS live (\(queued))"
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

        return "cassette"
    }

    func statusImage(appearance: NSAppearance, playbackActive: Bool = false) -> NSImage? {
        if !muted && speaking == 0 && !playbackActive {
            return cassetteStatusImage(accessibilityDescription: title, hasMessages: queued > 0, liveActive: mode == "live", appearance: appearance)
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}

private func cassetteStatusImage(accessibilityDescription: String, hasMessages: Bool, liveActive: Bool, appearance: NSAppearance) -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 20))
    image.accessibilityDescription = accessibilityDescription
    image.isTemplate = false

    image.lockFocus()
    defer {
        image.unlockFocus()
    }

    let strokeColor = menuBarIconStrokeColor(appearance: appearance)
    strokeColor.setStroke()

    let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 4.7, width: 16, height: 11.4), xRadius: 2.5, yRadius: 2.5)
    body.lineWidth = 1.55
    body.stroke()

    let window = NSBezierPath(roundedRect: NSRect(x: 5.6, y: 12.3, width: 8.8, height: 2.3), xRadius: 0.8, yRadius: 0.8)
    window.lineWidth = 1
    window.stroke()

    let leftReel = NSBezierPath(ovalIn: NSRect(x: 4.7, y: 6.9, width: 3.8, height: 3.8))
    leftReel.lineWidth = 1.2
    leftReel.stroke()

    let rightReel = NSBezierPath(ovalIn: NSRect(x: 11.5, y: 6.9, width: 3.8, height: 3.8))
    rightReel.lineWidth = 1.2
    rightReel.stroke()

    let tapeLine = NSBezierPath()
    tapeLine.lineWidth = 1
    tapeLine.move(to: NSPoint(x: 8.5, y: 8.8))
    tapeLine.line(to: NSPoint(x: 11.5, y: 8.8))
    tapeLine.stroke()

    if liveActive || hasMessages {
        (liveActive ? menuBarLiveAccentColor(appearance: appearance) : menuBarQueuedAccentColor(appearance: appearance)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 13.8, y: 12.7, width: 4.2, height: 4.2)).fill()
    }

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
    let commandPaletteShortcut: KeyboardShortcut
    let firstStartSetupComplete: Bool
}

#if !APP_STORE
struct RelayCliInstallStatus {
    let status: String
    let sourcePath: String?
    let sourceSignature: String?
    let targetPath: String
    let targetDirectoryOnPath: Bool
    let version: String
    let message: String

    var shouldPrompt: Bool {
        status == "missing" || status == "stale"
    }
}

struct RelayCliInstallResult {
    let succeeded: Bool
    let title: String
    let detail: String
}

struct RelayCliCommandResult {
    let status: Int
    let stdout: String
    let stderr: String
}

private func parseRelayCliInstallStatus(_ json: String) -> RelayCliInstallStatus {
    guard
        let data = json.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return RelayCliInstallStatus(
            status: "source-missing",
            sourcePath: nil,
            sourceSignature: nil,
            targetPath: "/usr/local/bin/relay",
            targetDirectoryOnPath: false,
            version: "unknown",
            message: "could not parse relay CLI status"
        )
    }

    let status = object["status"] as? String ?? "source-missing"
    let sourcePath = object["sourcePath"] as? String
    let targetPath = object["targetPath"] as? String ?? "/usr/local/bin/relay"
    let targetDirectoryOnPath = object["targetDirectoryOnPath"] as? Bool ?? false
    let version = object["version"] as? String ?? "unknown"
    let message = object["message"] as? String ?? "relay CLI status unavailable"
    let sourceSignature = object["sourceSignature"] as? String

    return RelayCliInstallStatus(
        status: status,
        sourcePath: sourcePath,
        sourceSignature: sourceSignature,
        targetPath: targetPath,
        targetDirectoryOnPath: targetDirectoryOnPath,
        version: version,
        message: message
    )
}

private func deletingLastPathComponent(_ path: String) -> String {
    URL(fileURLWithPath: path).deletingLastPathComponent().path
}

private func relayCliSettingsMessage(_ status: RelayCliInstallStatus) -> String {
    let pathNote = status.targetDirectoryOnPath
        ? "Agents should be able to run `relay` directly from that path."
        : "Add \(deletingLastPathComponent(status.targetPath)) to PATH so agents can run `relay` without a full path."

    switch status.status {
    case "current":
        return "Installed at \(status.targetPath). \(pathNote)"
    case "stale":
        return "An older TSRS relay CLI is installed at \(status.targetPath). Update it to match bundled version \(status.version). \(pathNote)"
    case "foreign":
        return "\(status.targetPath) already exists but does not look like TSRS relay. Safe overwrite is blocked; choose another accessible path or move the existing binary."
    case "source-missing":
        return "The bundled app-contents CLI could not be found. Rebuild or reinstall the app."
    default:
        return "Not installed at \(status.targetPath). Install there for normal agent use, or copy the bundled app-contents path for manual agent instructions. \(pathNote)"
    }
}
#endif

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
                speechVoiceIdentifier: speechVoiceIdentifier(settings),
                commandPaletteShortcut: commandPaletteShortcut(settings),
                firstStartSetupComplete: firstStartSetupComplete(settings)
            )
        } ?? defaultSettings()
    }

    func needsFirstStartSetup() -> Bool {
        !loadSettings().firstStartSetupComplete
    }

    func completeFirstStartSetup() {
        write { database in
            setSetting(database, key: "first_start_setup_complete", value: "true")
        }
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
        guard mode == "ready" || mode == "focus" || mode == "live" else {
            NSLog("TSRS native store rejected invalid mode: \(mode)")
            return
        }

        write { database in
            setSetting(database, key: "mode", value: mode)
            if mode != "live" {
                clearLiveBatch(database)
            }
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

    func saveSettings(inactiveLineCombinerCommand: String, voiceIdentifier: String, commandPaletteShortcut: KeyboardShortcut) {
        guard profile != "app-store" else {
            saveVoiceIdentifier(voiceIdentifier)
            saveCommandPaletteShortcut(commandPaletteShortcut)
            return
        }

        write { database in
            setSetting(database, key: "inactive_line_combiner_command", value: resetBlankCommand(inactiveLineCombinerCommand, fallback: defaultInactiveLineCombinerCommand))
            setSetting(database, key: "speech_voice_identifier", value: voiceIdentifier)
            setSetting(database, key: "command_palette_shortcut", value: commandPaletteShortcut.identifier)
        }
    }

    func saveCommandPaletteShortcut(_ shortcut: KeyboardShortcut) {
        write { database in
            setSetting(database, key: "command_palette_shortcut", value: shortcut.identifier)
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

    func enqueue(_ input: NewRelayInput) throws -> NativeRelay? {
        let relay = try normalizeRelay(input)
        var inserted: NativeRelay?
        let snapshot = writeResult { database in
            let settings = loadRawSettings(database)
            return (
                settings: settings,
                existing: latestQueuedRelay(database, line: relay.line).map {
                    RelayCliStoredRelay(id: $0.id, line: $0.line, message: $0.message, type: $0.type, priority: $0.priority, status: $0.status)
                }
            )
        }
        let settings = snapshot?.settings ?? [:]
        let activeLine = settings["active_line"]
        let shouldCombineInactive = playbackMode(settings["mode"]) != "live" && activeLine != nil && relay.line != activeLine
        let combinedRelay: NormalizedRelay?

        if shouldCombineInactive, let activeLine {
            do {
                combinedRelay = try combineInactiveRelay(
                    activeLine: activeLine,
                    incoming: relay,
                    existing: snapshot?.existing,
                    command: inactiveLineCombinerCommand(settings)
                ).relay
            } catch {
                NSLog("TSRS inactive-line combiner failed: \(error)")
                combinedRelay = relay
            }
        } else {
            combinedRelay = nil
        }

        write { database in
            let currentActiveLine = loadRawSettings(database)["active_line"]
            let stillInactive = shouldCombineInactive && currentActiveLine != relay.line

            if stillInactive {
                guard let combinedRelay else {
                    return
                }
                clearQueued(database, line: relay.line)
                inserted = insertRelay(database, combinedRelay)
            } else {
                inserted = insertRelay(database, relay)
            }

            if inserted != nil && !stillInactive {
                execute(database, """
                    INSERT OR IGNORE INTO settings (key, value)
                    VALUES ('active_line', ?)
                """, [relay.line])
            }
        }

        return inserted
    }

    private func insertRelay(_ database: OpaquePointer, _ relay: NormalizedRelay) -> NativeRelay? {
        returningRelay(database, """
            INSERT INTO relays (
              line, message, type, priority, session, app, cwd, url, status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
            RETURNING id, line, message, type, priority, status, created_at, updated_at
        """, [
            relay.line,
            relay.message,
            relay.type,
            relay.priority,
            relay.session,
            relay.app,
            relay.cwd,
            relay.url,
            nowString(),
            nowString()
        ])
    }

    private func latestQueuedRelay(_ database: OpaquePointer, line: String) -> NativeRelay? {
        returningRelay(database, """
            SELECT id, line, message, type, priority, status, created_at, updated_at
            FROM relays
            WHERE status = 'queued' AND line = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 1
        """, [line])
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
            clearQueued(database, line: line)
        }
    }

    private func clearQueued(_ database: OpaquePointer, line: String) {
        execute(database, """
            DELETE FROM relays
            WHERE status = 'queued' AND line = ?
        """, [line])
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
                if playbackMode(settings["mode"]) != "live", let activeLine = settings["active_line"], queuedCount(database, line: activeLine) > 0 {
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

    func claimQueuedMessageForNativeSpeech(line: String, id: Int) -> NativeSpeechClaim? {
        writeResult { database in
            expireStaleRelays(database)
            failStaleSpeaking(database)
            let settings = loadRawSettings(database)
            guard settings["muted"] != "true" else {
                return nil
            }

            guard let relay = returningRelay(database, """
                UPDATE relays
                SET status = 'speaking', updated_at = ?
                WHERE id = ? AND line = ? AND status = 'queued'
                RETURNING id, line, message, type, priority, status, created_at, updated_at
            """, [nowString(), String(id), line]) else {
                return nil
            }

            return NativeSpeechClaim(
                id: relay.id,
                text: spokenText(relay, includeLine: shouldPrefixSpokenLine(database, line: relay.line))
            )
        }
    }

    func recentMessages(line: String, limit: Int = 20) -> [LineMessage] {
        withWriteDatabase { database in
            expireStaleRelays(database)
            failStaleSpeaking(database)
            var messages: [LineMessage] = []
            query(database, """
                SELECT id, line, message, status, created_at, updated_at
                FROM relays
                WHERE line = ? AND status IN ('queued', 'heard')
                ORDER BY
                  CASE status WHEN 'queued' THEN 0 ELSE 1 END,
                  CASE
                    WHEN status = 'queued' AND priority = 'high' THEN 0
                    WHEN status = 'queued' AND priority = 'normal' THEN 1
                    WHEN status = 'queued' THEN 2
                    ELSE 0
                  END,
                  CASE WHEN status = 'queued' THEN created_at END ASC,
                  CASE WHEN status = 'heard' THEN updated_at END DESC,
                  id DESC
                LIMIT ?
            """, [line, String(limit)]) { statement in
                messages.append(LineMessage(
                    id: Int(sqlite3_column_int(statement, 0)),
                    line: columnString(statement, 1) ?? "",
                    message: columnString(statement, 2) ?? "",
                    status: columnString(statement, 3) ?? "queued",
                    createdAt: columnString(statement, 4) ?? "",
                    updatedAt: columnString(statement, 5) ?? ""
                ))
            }
            return messages
        } ?? []
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
        let path = relayCliDatabasePath()
        createDatabaseDirectory(path)
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }

        sqlite3_busy_timeout(database, 2_000)
        migrate(database)
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
        let path = relayCliDatabasePath()
        createDatabaseDirectory(path)
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                NSLog("TSRS native store write open failed: \(sqliteError(database))")
                sqlite3_close(database)
            } else {
                NSLog("TSRS native store write open failed")
            }
            return nil
        }

        sqlite3_busy_timeout(database, 2_000)
        migrate(database)
        defer {
            sqlite3_close(database)
        }

        return mutation(database)
    }

    private func migrate(_ database: OpaquePointer) {
        executeBatch(database, """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS relays (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              line TEXT NOT NULL,
              message TEXT NOT NULL,
              type TEXT NOT NULL,
              priority TEXT NOT NULL,
              session TEXT,
              app TEXT,
              cwd TEXT,
              url TEXT,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
        """)

        execute(database, "INSERT OR IGNORE INTO schema_migrations (version) VALUES (1)")
        setSettingIfMissing(database, key: "mode", value: "focus")
        setSettingIfMissing(database, key: "muted", value: "false")
        setSettingIfMissing(database, key: "inactive_line_combiner", value: "none")
        setSettingIfMissing(database, key: "inactive_line_combiner_command", value: defaultInactiveLineCombinerCommand)
        setSettingIfMissing(database, key: "speech_command", value: defaultSpeechCommand)
        setSettingIfMissing(database, key: "first_start_setup_complete", value: defaultFirstStartSetupCompleteValue(database))
        setSettingIfMissing(database, key: "command_palette_shortcut", value: KeyboardShortcut.defaultCommandPalette.identifier)
        migrateLegacyCombinerSetting(database)
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

    private func executeBatch(_ database: OpaquePointer, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)

        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? sqliteError(database)
            sqlite3_free(error)
            NSLog("TSRS native store migration failed: \(message)")
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

    private func setSettingIfMissing(_ database: OpaquePointer, key: String, value: String) {
        execute(database, """
            INSERT OR IGNORE INTO settings (key, value)
            VALUES (?, ?)
        """, [key, value])
    }

    private func migratedInactiveLineCombinerCommand(_ database: OpaquePointer) -> String {
        let legacy = loadRawSettings(database)["inactive_line_combiner"]

        if legacy == "llm" {
            return "llm prompt <input> --system <system> --no-stream --no-log"
        }

        if legacy == "apfel" {
            return "apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>"
        }

        return defaultInactiveLineCombinerCommand
    }

    private func migrateLegacyCombinerSetting(_ database: OpaquePointer) {
        let settings = loadRawSettings(database)

        guard settings["inactive_line_combiner_command"] == defaultInactiveLineCombinerCommand else {
            return
        }

        let migrated = migratedInactiveLineCombinerCommand(database)

        if migrated != defaultInactiveLineCombinerCommand {
            setSetting(database, key: "inactive_line_combiner_command", value: migrated)
        }
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

        guard settings["muted"] != "true" else {
            return nil
        }

        let mode = playbackMode(settings["mode"])
        if mode == "live" {
            return claimNextForLive(database)
        }

        guard mode == "ready" else {
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

    private func claimNextForLive(_ database: OpaquePointer) -> NativeRelay? {
        if let batch = liveBatch(database), let relay = claimNextForLine(database, line: batch.line, maxId: batch.maxId) {
            return relay
        }

        clearLiveBatch(database)

        guard let batch = startNextLiveBatch(database) else {
            return nil
        }

        return claimNextForLine(database, line: batch.line, maxId: batch.maxId)
    }

    private func liveBatch(_ database: OpaquePointer) -> (line: String, maxId: Int)? {
        let settings = loadRawSettings(database)
        guard
            let line = settings["live_batch_line"],
            !line.isEmpty,
            let maxIdValue = settings["live_batch_max_id"],
            let maxId = Int(maxIdValue)
        else {
            return nil
        }
        return (line, maxId)
    }

    private func startNextLiveBatch(_ database: OpaquePointer) -> (line: String, maxId: Int)? {
        var batch: (line: String, maxId: Int)?
        query(database, """
            SELECT line, MAX(id) AS max_id
            FROM relays
            WHERE status = 'queued'
              AND line = (
                SELECT line
                FROM relays
                WHERE status = 'queued'
                ORDER BY
                  CASE priority
                    WHEN 'high' THEN 0
                    WHEN 'normal' THEN 1
                    ELSE 2
                  END,
                  created_at ASC,
                  id ASC
                LIMIT 1
              )
            GROUP BY line
        """) { statement in
            if let line = columnString(statement, 0) {
                batch = (line, Int(sqlite3_column_int(statement, 1)))
            }
        }

        guard let batch else {
            return nil
        }

        setSetting(database, key: "active_line", value: batch.line)
        setSetting(database, key: "live_batch_line", value: batch.line)
        setSetting(database, key: "live_batch_max_id", value: String(batch.maxId))
        return batch
    }

    private func clearLiveBatch(_ database: OpaquePointer) {
        setSetting(database, key: "live_batch_line", value: "")
        setSetting(database, key: "live_batch_max_id", value: "0")
    }

    private func claimNextForLine(_ database: OpaquePointer, line: String, maxId: Int? = nil) -> NativeRelay? {
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
              WHERE status = 'queued' AND line = ? AND (? IS NULL OR id <= ?)
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
        """, [nowString(), line, maxId.map(String.init), maxId.map(String.init)])
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

    private func commandPaletteShortcut(_ settings: [String: String]) -> KeyboardShortcut {
        KeyboardShortcut(identifier: settings["command_palette_shortcut"])
    }

    private func speechVoiceIdentifier(_ settings: [String: String]) -> String? {
        let identifier = settings["speech_voice_identifier"] ?? defaultSpeechVoiceIdentifier

        if availableSpeechVoiceOptions().contains(where: { $0.identifier == identifier }) {
            return identifier
        }

        return defaultSpeechVoiceIdentifier
    }

    private func firstStartSetupComplete(_ settings: [String: String]) -> Bool {
        settings["first_start_setup_complete"] == "true"
    }

    private func defaultFirstStartSetupCompleteValue(_ database: OpaquePointer) -> String {
        hasExistingSetupSignal(database) ? "true" : "false"
    }

    private func hasExistingSetupSignal(_ database: OpaquePointer) -> Bool {
        let setupKeys = [
            "active_line",
            "command_palette_shortcut",
            "speech_voice_identifier",
            "last_spoken_line",
        ]
        let settings = loadRawSettings(database)

        if setupKeys.contains(where: { settings[$0] != nil }) {
            return true
        }

        return scalarInt(database, "SELECT COUNT(*) FROM relays") > 0
    }

    private func scalarInt(_ database: OpaquePointer, _ sql: String, _ values: [String?] = []) -> Int {
        var value = 0
        query(database, sql, values) { statement in
            value = Int(sqlite3_column_int(statement, 0))
        }
        return value
    }
}


private func createDatabaseDirectory(_ path: String) {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path

    do {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    } catch {
        NSLog("TSRS native store could not create database directory \(directory): \(error.localizedDescription)")
    }
}

private func defaultStatus() -> QueueStatus {
    QueueStatus(mode: "focus", muted: false, queued: 0, speaking: 0, heard: 0, inactiveLineCombiner: "none", activeLine: nil, lines: [], lineSources: [:])
}

private func defaultSettings() -> SettingsSnapshot {
    SettingsSnapshot(inactiveLineCombinerCommand: "", speechVoiceIdentifier: defaultSpeechVoiceIdentifier, commandPaletteShortcut: .defaultCommandPalette, firstStartSetupComplete: false)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func appStoreUnavailableCommand(_ feature: String) -> String {
    "# External \(feature) command execution is unavailable in the App Store-safe profile."
}
