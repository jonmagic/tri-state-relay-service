import XCTest
@testable import Tri_State_Relay_Service

final class TriStateRelayServiceTests: XCTestCase {
    func testDefaultStatusStartsFocused() throws {
        let databasePath = isolatedTriStateDatabasePath()
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: databasePath).deletingLastPathComponent().path)
        }

        let store = NativeRelayStore(profile: "direct")
        let status = store.loadStatus()

        XCTAssertEqual(status.mode, "focus")
    }

    func testSetupViewDoesNotShowStaleFirstStartCopy() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertFalse(source.contains("Two quick choices. TSRS stays quiet in Focus mode."))
        XCTAssertFalse(source.contains("Current shortcut:"))
        XCTAssertFalse(source.contains("Control + Option + Command + V is reserved."))
        XCTAssertTrue(source.contains("Click the button, then press a valid key combination."))
    }

    func testSetupViewIncludesOpenAtLoginOption() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("import ServiceManagement"))
        XCTAssertTrue(source.contains("3. Open at Login"))
        XCTAssertTrue(source.contains("Open Tri-State Relay Service at login"))
        XCTAssertTrue(source.contains("SMAppService.mainApp.register()"))
        XCTAssertTrue(source.contains("SMAppService.mainApp.unregister()"))
    }

    func testAppDoesNotPromptForCliInstallOnLaunch() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertFalse(source.contains("promptForRelayCliInstallIfNeeded"))
        XCTAssertFalse(source.contains("Install the relay CLI?"))
        XCTAssertFalse(source.contains("relayCliInstallPromptSuppressed"))
    }

    func testAppUsesDarwinWakeInsteadOfShortIdlePolling() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("CFNotificationCenterAddObserver("))
        XCTAssertTrue(source.contains("relayQueueChangedDarwinNotification as CFString"))
        XCTAssertTrue(source.contains("queueWakeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15"))
        XCTAssertTrue(source.contains("safetyRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60"))
        XCTAssertTrue(source.contains("safetyRefreshTimer?.tolerance = 15"))
        XCTAssertTrue(source.contains("refreshAndPlayIfEligible()"))
        XCTAssertTrue(source.contains("if model.status.mode == \"ready\" || model.status.mode == \"live\""))
        XCTAssertTrue(source.contains("inputCaptureRetryTimer = Timer.scheduledTimer(withTimeInterval: 3"))
        XCTAssertTrue(source.contains("inputCaptureRetryTimer?.tolerance = 1"))
        XCTAssertTrue(source.contains("shouldRetryAfterInputCapture(line: line)"))
        XCTAssertFalse(source.contains("scheduledTimer(withTimeInterval: 2"))
        XCTAssertFalse(source.contains("schedulePlaybackRefresh"))
        XCTAssertFalse(source.contains("playbackRefreshTimer"))
    }

    func testPrivilegedCliInstallUsesQuotedAppleScriptArguments() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("installRelayCliWithAdministratorPrivileges(sourcePath: preflight.sourcePath, targetPath: preflight.targetPath)"))
        XCTAssertTrue(source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/osascript\")"))
        XCTAssertTrue(source.contains("process.arguments = [\"-e\", script, \"--\"] + arguments"))
        XCTAssertTrue(source.contains("quoted form of src"))
        XCTAssertTrue(source.contains("quoted form of dst"))
        XCTAssertTrue(source.contains("with administrator privileges"))
    }

    func testSettingsWindowSupportsKeyboardNavigationAndDismissal() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("final class SettingsWindow: NSWindow"))
        XCTAssertTrue(source.contains("case kVK_UpArrow:"))
        XCTAssertTrue(source.contains("case kVK_DownArrow:"))
        XCTAssertTrue(source.contains("case kVK_Escape:"))
        XCTAssertTrue(source.contains("override func cancelOperation(_ sender: Any?)"))
        XCTAssertTrue(source.contains("event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == \"q\""))
        XCTAssertTrue(source.contains("NSApplication.shared.terminate(nil)"))
        XCTAssertTrue(source.contains("final class SettingsKeyboardFocusView: NSView"))
        XCTAssertTrue(source.contains("window?.makeFirstResponder(keyboardNavigationFocusView)"))
    }

    func testSettingsWindowUsesSeamlessTitlebar() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]"))
        XCTAssertTrue(source.contains("window.titleVisibility = .hidden"))
        XCTAssertTrue(source.contains("window.titlebarAppearsTransparent = true"))
        XCTAssertTrue(source.contains("cliSectionRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 32)"))
        XCTAssertTrue(source.contains("settingsTabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 32)"))
        XCTAssertTrue(source.contains("private let advancedSectionButton = NSButton(title: \"Advanced\""))
        XCTAssertTrue(source.contains("settingsTabView.tabViewItem(at: 3).view = advancedTabView()"))
    }

    func testSettingsSidebarShowsSubtleVersion() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("let appVersion = Bundle.main.object(forInfoDictionaryKey: \"CFBundleShortVersionString\") as? String ?? relayCliVersion"))
        XCTAssertTrue(source.contains("private let versionLabel = NSTextField(labelWithString: \"Version \\(appVersion)\""))
        XCTAssertTrue(source.contains("versionLabel.textColor = .tertiaryLabelColor"))
        XCTAssertTrue(source.contains("versionLabel.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16)"))
    }

    func testSettingsControlsExposeStableAccessibilityIdentifiers() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("window.setAccessibilityIdentifier(\"tsrs.settings.window\")"))
        XCTAssertTrue(source.contains("settingsTabView.setAccessibilityIdentifier(\"tsrs.settings.tabs\")"))
        XCTAssertTrue(source.contains("configureAccessibility(cliSectionButton, identifier: \"tsrs.settings.sidebar.setup.button\""))
        XCTAssertTrue(source.contains("configureAccessibility(voiceSectionButton, identifier: \"tsrs.settings.sidebar.voice.button\""))
        XCTAssertTrue(source.contains("configureAccessibility(secondarySectionButton, identifier: \"tsrs.settings.sidebar.secondary.button\""))
        XCTAssertTrue(source.contains("configureAccessibility(advancedSectionButton, identifier: \"tsrs.settings.sidebar.advanced.button\""))
        XCTAssertTrue(source.contains("container.setAccessibilityIdentifier(\"tsrs.settings.setup.panel\")"))
        XCTAssertTrue(source.contains("scrollContainer.setAccessibilityIdentifier(\"tsrs.settings.voice.panel\")"))
        XCTAssertTrue(source.contains("container.setAccessibilityIdentifier(\"tsrs.settings.combiner.panel\")"))
        XCTAssertTrue(source.contains("scrollContainer.setAccessibilityIdentifier(\"tsrs.settings.advanced.panel\")"))
        XCTAssertTrue(source.contains("configureAccessibility(cliStatusView, identifier: \"tsrs.settings.setup.cli-status\""))
        XCTAssertTrue(source.contains("configureAccessibility(voiceCommandErrorView, identifier: \"tsrs.settings.voice.command-error\""))
        XCTAssertTrue(source.contains("configureAccessibility(cleanupRetentionStatusView, identifier: \"tsrs.settings.advanced.cleanup-retention-status\""))
    }

    func testDebugOpenSettingsNotificationIsScopedToSettingsWindow() throws {
        let appSource = try triStateRelayServiceSource()
        let coreSource = try relayCoreSource()

        XCTAssertTrue(coreSource.contains("let relayDebugOpenSettingsDarwinNotification = \"com.jonmagic.tristaterelayservice.debug.open-settings\""))
        XCTAssertTrue(coreSource.contains("let relayDebugOpenSettingsPanels = [\"setup\", \"voice\", \"secondary\", \"advanced\"]"))
        XCTAssertTrue(coreSource.contains("postRelayDebugOpenSettingsNotification()"))
        XCTAssertTrue(coreSource.contains("relayDebugOpenSettingsNotificationName(panel: panel)"))
        XCTAssertTrue(appSource.contains("registerDebugOpenSettingsObserver()"))
        XCTAssertTrue(appSource.contains("app.showSettingsPanel(panel)"))
        XCTAssertTrue(appSource.contains("func selectPanel(named panel: String?)"))
        XCTAssertFalse(appSource.contains("relayDebugOpenSettingsDarwinNotification as CFString,\n            nil,\n            .deliverImmediately\n        )\n    }\n\n    private func scheduleQueueWakeRefresh"))
    }

    func testSettingsScreenshotCaptureWorkflowUsesAccessibilityIdentifiersAndNoPlaybackDebugAction() throws {
        let script = try repositoryFileSource("scripts/capture-settings-ui.sh")
        let docs = try repositoryFileSource("docs/development.md")
        let gitignore = try repositoryFileSource(".gitignore")
        let focusRange = try XCTUnwrap(script.range(of: "\"$relay_cli\" focus >/dev/null"))
        let restartRange = try XCTUnwrap(script.range(of: "scripts/restart-macos-app.sh"))

        XCTAssertTrue(script.contains("debug open-settings"))
        XCTAssertTrue(script.contains("debug open-settings --panel \"$panel\""))
        XCTAssertLessThan(script.distance(from: script.startIndex, to: focusRange.lowerBound), script.distance(from: script.startIndex, to: restartRange.lowerBound))
        XCTAssertTrue(script.contains("capturing full-screen Settings screenshots"))
        XCTAssertTrue(script.contains("screencapture -x -l"))
        XCTAssertTrue(script.contains("screencapture -x \"$artifact_root/${name}.png\""))
        XCTAssertFalse(script.contains("/usr/bin/say"))
        XCTAssertFalse(script.contains("relay\" live"))
        XCTAssertFalse(script.contains("relay\" ready"))
        XCTAssertTrue(docs.contains("scripts/capture-settings-ui.sh"))
        XCTAssertTrue(docs.contains("Accessibility permission"))
        XCTAssertTrue(docs.contains(".artifacts/settings-ui/"))
        XCTAssertTrue(gitignore.contains(".artifacts/"))
    }

    func testStatusMenuOrderKeepsCoreActionsSimple() throws {
        let source = try triStateRelayServiceSource()
        guard
            let showMenuRange = source.range(of: "    private func showMenu()"),
            let endRange = source[showMenuRange.lowerBound...].range(of: "    private func playCurrentLineFromHotKey()")
        else {
            return XCTFail("showMenu boundaries are missing")
        }
        let showMenuSource = source[showMenuRange.lowerBound..<endRange.lowerBound]

        let playNextOffset = showMenuSource.distance(from: showMenuSource.startIndex, to: showMenuSource.range(of: "menu.addItem(menuItem(\"Play Next\"")!.lowerBound)
        let linesOffset = showMenuSource.distance(from: showMenuSource.startIndex, to: showMenuSource.range(of: "for item in lineMenuItems()")!.lowerBound)
        let muteOffset = showMenuSource.distance(from: showMenuSource.startIndex, to: showMenuSource.range(of: "menu.addItem(menuItem(\"Mute\"")!.lowerBound)
        let settingsOffset = showMenuSource.distance(from: showMenuSource.startIndex, to: showMenuSource.range(of: "menu.addItem(menuItem(\"Settings...\"")!.lowerBound)
        let quitOffset = showMenuSource.distance(from: showMenuSource.startIndex, to: showMenuSource.range(of: "menu.addItem(menuItem(\"Quit\"")!.lowerBound)

        XCTAssertLessThan(playNextOffset, linesOffset)
        XCTAssertLessThan(linesOffset, muteOffset)
        XCTAssertLessThan(muteOffset, settingsOffset)
        XCTAssertLessThan(settingsOffset, quitOffset)
        XCTAssertFalse(showMenuSource.contains("relayCliMenuTitle"))
    }

    func testCommandPaletteOmitsCliInstallAndNoQueuedMessagesActions() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertFalse(source.contains("CommandPaletteCommand(title: model.relayCliMenuTitle()"))
        XCTAssertFalse(source.contains("CommandPaletteCommand(title: \"No Queued Messages\""))
    }

    func testCommandPaletteListsActiveLinesAfterPlayNext() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("commands.append(contentsOf: model.status.menuLines.compactMap { line in"))
        XCTAssertFalse(source.contains("CommandPaletteCommand(title: \"Play Next: \\(line.line)\""))
        XCTAssertFalse(source.contains("guard line.queued > 0 else"))
    }

    func testVoicePanelUsesConciseUserFacingHelperText() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("Exactly one uncommented command must write an audio file for TSRS to play."))
        XCTAssertFalse(source.contains("Direct builds use the app-owned /usr/bin/say path"))
        XCTAssertFalse(source.contains("Natural installed voices are listed first when available."))
    }

    func testVoiceAndCombinerHelpersSitBelowSectionLabels() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("views.append(contentsOf: [commandLabel, commandNote, commandScrollView, voiceCommandStatusView, diagnosticsLabel, voiceCommandErrorView])"))
        XCTAssertTrue(source.contains("NSStackView(views: [title, combinerLabel, combinerNote, scrollView])"))
    }

    func testAdvancedPanelExposesCleanupRetentionMinutes() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("let retentionLabel = NSTextField(labelWithString: \"Local cleanup retention\")"))
        XCTAssertTrue(source.contains("cleanupRetentionField.placeholderString = String(defaultCleanupRetentionMinutes)"))
        XCTAssertTrue(source.contains("@objc private func saveCleanupRetention"))
    }

    func testVoicePanelExposesVoiceCommandTemplate() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("private let voiceCommandTextView = NSTextView()"))
        XCTAssertTrue(source.contains("voiceCommandTextView.string = settings.voiceCommand"))
        XCTAssertTrue(source.contains("let commandLabel = NSTextField(labelWithString: \"Voice command\")"))
        XCTAssertTrue(source.contains("Exactly one uncommented command must write an audio file for TSRS to play."))
        XCTAssertTrue(source.contains("commandScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)"))
        XCTAssertTrue(source.contains("configuredTextViewScrollView(voiceCommandTextView, wrapsLines: true)"))
        XCTAssertTrue(source.contains("resetVoiceCommandTextViewScroll()"))
    }

    func testCommandPaletteRendersWindowAroundSelectedCommand() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("let visibleItems = visibleCommands()"))
        XCTAssertTrue(source.contains("let startIndex = min(max(selectedIndex - limit + 1, 0), maxStartIndex)"))
        XCTAssertFalse(source.contains("filteredCommands.prefix(5)"))
    }

    func testSelectedLineMessageRowsWrapInsteadOfTruncating() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("titleField.lineBreakMode = selected ? .byWordWrapping : .byTruncatingTail"))
        XCTAssertTrue(source.contains("titleField.preferredMaxLayoutWidth = Self.panelWidth - (Self.contentInset * 2)"))
        XCTAssertTrue(source.contains("stack.trailingAnchor.constraint(equalTo: row.trailingAnchor"))
        XCTAssertTrue(source.contains("resizeWindow(rowHeights: resultsStack.arrangedSubviews.map(\\.fittingSize.height))"))
        XCTAssertTrue(source.contains("if selected {\n            constraints.append(stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8))"))
    }

    func testCommandPaletteMouseSelectionAvoidsRedundantRenders() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("guard nextIndex != selectedIndex else"))
        XCTAssertTrue(source.contains("private func moveSelection(_ delta: Int) -> Bool"))
        XCTAssertTrue(source.contains("return false\n        }\n\n        selectedIndex = nextIndex"))
        XCTAssertTrue(source.contains("final class RoundedCommandPaletteBackgroundView: NSVisualEffectView {\n    var onScroll: ((Int) -> Bool)?"))
        XCTAssertTrue(source.contains("final class PaletteResultRowView: NSView {\n    var action: (() -> Void)?\n    var onHover: (() -> Void)?\n    var onScroll: ((Int) -> Bool)?"))
        XCTAssertTrue(source.contains("_ = onScroll?(delta)"))
        XCTAssertTrue(source.contains("if selector == #selector(NSText.copy(_:)), copySelectedCommandText()"))
        XCTAssertTrue(source.contains("NSPasteboard.general.setString(copyText, forType: .string)\n        close()\n        restorePreviousApplication()"))
        XCTAssertTrue(source.contains("options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect]"))
        XCTAssertTrue(source.contains("override func mouseMoved(with event: NSEvent)"))
        XCTAssertFalse(source.contains("mouseEntered(with event:"))
        XCTAssertTrue(source.contains("override func hitTest(_ point: NSPoint) -> NSView?"))
        XCTAssertTrue(source.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool"))
        XCTAssertTrue(source.contains("override func keyDown(with event: NSEvent)"))
    }

    func testCommandPaletteUsesRaycastStyleDynamicAppearance() throws {
        let source = try triStateRelayServiceSource()
        guard
            let paletteRange = source.range(of: "final class CommandPaletteWindowController"),
            let endRange = source[paletteRange.lowerBound...].range(of: "private func configureSidebarButton")
        else {
            return XCTFail("command palette boundaries are missing")
        }
        let paletteSource = source[paletteRange.lowerBound..<endRange.lowerBound]

        XCTAssertTrue(paletteSource.contains("let content = RoundedCommandPaletteBackgroundView"))
        XCTAssertTrue(paletteSource.contains("final class RoundedCommandPaletteBackgroundView: NSVisualEffectView"))
        XCTAssertTrue(paletteSource.contains("maskImage = roundedMaskImage(size: bounds.size, radius: 18)"))
        XCTAssertTrue(paletteSource.contains("content.material = .popover"))
        XCTAssertTrue(paletteSource.contains("private static let contentInset: CGFloat = 18"))
        XCTAssertTrue(paletteSource.contains("private static let rowOuterPadding: CGFloat = 6"))
        XCTAssertTrue(paletteSource.contains("private static let searchHeight: CGFloat = 34"))
        XCTAssertTrue(paletteSource.contains("private static let searchToDividerSpacing: CGFloat = 2"))
        XCTAssertTrue(paletteSource.contains("private let headerDivider = NSBox()"))
        XCTAssertTrue(paletteSource.contains("final class CommandPaletteSearchField: NSTextField"))
        XCTAssertTrue(paletteSource.contains("placeholderAttributedString = NSAttributedString"))
        XCTAssertTrue(paletteSource.contains("textColor = .labelColor"))
        XCTAssertTrue(paletteSource.contains("titleField.textColor = .labelColor"))
        XCTAssertTrue(paletteSource.contains("subtitleField.textColor = .secondaryLabelColor"))
        XCTAssertTrue(paletteSource.contains("withAlphaComponent(0.16)"))
        XCTAssertFalse(paletteSource.contains("CommandPaletteSearchField: NSSearchField"))
        XCTAssertFalse(paletteSource.contains("content.layer?.backgroundColor = resolvedColor(.windowBackgroundColor).cgColor"))
        XCTAssertFalse(paletteSource.contains("selectedMenuItemTextColor"))
    }

    func testCommandPaletteSupportsAndShowsQuitShortcut() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("final class CommandPalettePanel: NSPanel"))
        XCTAssertTrue(source.contains("panel.onQuit = {"))
        XCTAssertTrue(source.contains("CommandPaletteCommand(title: \"Quit\", subtitle: \"Command-Q\""))
        XCTAssertTrue(source.contains("event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == \"q\""))
    }

}

func triStateRelayServiceSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TriStateRelayService.swift")

    return try String(contentsOf: sourceURL, encoding: .utf8)
}

func relayCoreSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RelayCore.swift")

    return try String(contentsOf: sourceURL, encoding: .utf8)
}

func repositoryFileSource(_ relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

private func isolatedTriStateDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tsrs-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("relay.db")
        .path
}
