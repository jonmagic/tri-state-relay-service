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
