import XCTest
@testable import Tri_State_Relay_Service

final class TriStateRelayServiceTests: XCTestCase {
    func testDefaultStatusStartsFocused() throws {
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

        XCTAssertTrue(source.contains("Choose the voice TSRS uses when it speaks a relay. Use Preview to hear a sample."))
        XCTAssertFalse(source.contains("Direct builds use the app-owned /usr/bin/say path"))
        XCTAssertFalse(source.contains("Natural installed voices are listed first when available."))
    }

    func testVoiceAndCombinerHelpersSitBelowSectionLabels() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("NSStackView(views: [title, voiceLabel, voiceNote, voiceRow])"))
        XCTAssertTrue(source.contains("NSStackView(views: [title, combinerLabel, combinerNote, scrollView])"))
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
