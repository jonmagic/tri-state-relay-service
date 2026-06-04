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

    func testCommandPaletteSupportsAndShowsQuitShortcut() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("final class CommandPalettePanel: NSPanel"))
        XCTAssertTrue(source.contains("panel.onQuit = {"))
        XCTAssertTrue(source.contains("CommandPaletteCommand(title: \"Quit\", subtitle: \"Command-Q\""))
        XCTAssertTrue(source.contains("event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == \"q\""))
    }

    func testCommandPaletteOnlyShowsLinePlayNextWhenMultipleLinesAreQueued() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("let queuedLines = model.status.menuLines.filter { $0.queued > 0 }"))
        XCTAssertTrue(source.contains("if queuedLines.count > 1"))
        XCTAssertTrue(source.contains("CommandPaletteCommand(title: \"Play Next: \\(line.line)\""))
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
