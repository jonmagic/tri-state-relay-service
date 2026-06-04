import XCTest
import Carbon.HIToolbox
@testable import Tri_State_Relay_Service

final class PlaybackProfileTests: XCTestCase {
    func testSpeechPlaybackIsProfileGated() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertTrue(source.contains("#if APP_STORE\n        let utterance = AVSpeechUtterance(string: claim.text)"))
        XCTAssertTrue(source.contains("#else\n        let option = speechVoiceOption(identifier: model.loadSettings().speechVoiceIdentifier)"))
        XCTAssertTrue(source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/say\")"))
    }

    func testRelayProcessorIsNotReferencedByAppBundleCode() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertFalse(source.contains("relay-processor"))
    }

    func testCommandPaletteShortcutDefaultsToPlayNextShortcut() throws {
        let shortcut = KeyboardShortcut(identifier: nil)
        let plan = GlobalHotKeyRegistrationPlan.commandPalette(shortcut: shortcut)

        XCTAssertEqual(shortcut.identifier, "control-option-command-space")
        XCTAssertEqual(shortcut.displayName, "Control + Option + Command + Space")
        XCTAssertEqual(plan.id, 1)
        XCTAssertEqual(plan.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(plan.modifiers, UInt32(cmdKey | optionKey | controlKey))
    }

    func testCommandPaletteShortcutRoundTripsPersistedIdentifiers() throws {
        for option in KeyboardShortcut.availableCommandPaletteShortcuts {
            let decoded = KeyboardShortcut(identifier: option.identifier)
            let plan = GlobalHotKeyRegistrationPlan.commandPalette(shortcut: decoded)

            XCTAssertEqual(decoded, option)
            XCTAssertEqual(plan.keyCode, option.keyCode)
            XCTAssertEqual(plan.modifiers, option.modifiers)
        }
    }

    func testCommandPaletteShortcutRejectsUnknownPersistedIdentifier() throws {
        let shortcut = KeyboardShortcut(identifier: "control-option-command-v")
        let plan = GlobalHotKeyRegistrationPlan.commandPalette(shortcut: shortcut)

        XCTAssertEqual(shortcut, .defaultCommandPalette)
        XCTAssertEqual(plan.keyCode, UInt32(kVK_Space))
    }

    func testCommandPaletteShortcutCanBeChangedWithoutAppKitRegistration() throws {
        let shortcut = KeyboardShortcut(identifier: "control-option-command-p")
        let plan = GlobalHotKeyRegistrationPlan.commandPalette(shortcut: shortcut)

        XCTAssertEqual(shortcut.displayName, "Control + Option + Command + P")
        XCTAssertEqual(plan.keyCode, UInt32(kVK_ANSI_P))
        XCTAssertEqual(plan.modifiers, UInt32(cmdKey | optionKey | controlKey))
    }

    func testCommandPaletteShortcutOptionsExcludeFormerVShortcut() throws {
        XCTAssertFalse(KeyboardShortcut.availableCommandPaletteShortcuts.contains { $0.identifier == "control-option-command-v" })
        XCTAssertFalse(KeyboardShortcut.availableCommandPaletteShortcuts.contains { $0.keyCode == UInt32(kVK_ANSI_V) })
    }
}
