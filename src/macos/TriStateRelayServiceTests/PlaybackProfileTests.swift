import XCTest
import Carbon.HIToolbox
@testable import Tri_State_Relay_Service

final class PlaybackProfileTests: XCTestCase {
    func testSpeechPlaybackIsProfileGated() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertTrue(source.contains("#if APP_STORE\n        let utterance = AVSpeechUtterance(string: claim.text)"))
        XCTAssertTrue(source.contains("if commandIsEnabled(settings.voiceCommand)"))
        XCTAssertTrue(source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/say\")"))
    }

    func testExplicitReplayShowsPlaybackActivityWithoutQueueMutation() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("button.image = model.status.statusImage(appearance: button.effectiveAppearance, playbackActive: nativePlayback.isPlaying)"))
        XCTAssertTrue(source.contains("currentProcess != nil || currentAudioPlayer != nil || synthesizer.isSpeaking"))
        XCTAssertTrue(source.contains("onChange()\n        speakReplay(text)"))
    }

    func testRelayProcessorIsNotReferencedByAppBundleCode() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertFalse(source.contains("relay-processor"))
    }

    func testSayArgumentsUsePersistedSayVoiceName() throws {
        let option = SpeechVoiceOption(identifier: "say:Samantha", name: "Samantha", title: "Samantha")

        XCTAssertEqual(sayArguments(text: "Relay ready", option: option), ["-v", "Samantha", "Relay ready"])
    }

    func testSpeechVoiceOptionsStayValidForSayPlayback() throws {
        for option in availableSpeechVoiceOptions() where option.identifier.hasPrefix("say:") {
            XCTAssertEqual(sayArguments(text: "Relay ready", option: option), ["-v", option.name, "Relay ready"])
            XCTAssertFalse(option.name.isEmpty)
        }
    }

    func testVoiceCommandArgumentsExpandFileAndVoicePlaceholders() {
        XCTAssertEqual(
            voiceCommandArguments(
                ["-v", "<voice-id>", "-f", "<text-file>", "-o", "<output-file>"],
                textFile: "/tmp/relay.txt",
                outputFile: "/tmp/relay.aiff",
                voiceID: "Samantha"
            ),
            ["-v", "Samantha", "-f", "/tmp/relay.txt", "-o", "/tmp/relay.aiff"]
        )
    }

    func testStaleVoiceCommandDirectoriesAreCleanedUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tsrs-cleanup-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let stale = directory.appendingPathComponent("tsrs-voice-stale", isDirectory: true)
        let fresh = directory.appendingPathComponent("tsrs-voice-fresh", isDirectory: true)
        let unrelated = directory.appendingPathComponent("other-stale", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 10_000)
        let old = now.addingTimeInterval(-120 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: stale.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: unrelated.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fresh.path)

        removeStaleVoiceCommandDirectories(in: directory, now: now, staleMinutes: 60)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testChangingVoiceSelectionDoesNotAutoPreview() throws {
        let source = try triStateRelayServiceSource()
        guard let selectVoiceRange = source.range(of: "@objc private func selectVoice") else {
            return XCTFail("selectVoice action is missing")
        }
        let remainder = source[selectVoiceRange.lowerBound...]
        guard let endRange = remainder.range(of: "    @objc private func installRelayCliFromSetup") else {
            return XCTFail("selectVoice action boundary is missing")
        }
        let selectVoiceBody = remainder[..<endRange.lowerBound]

        XCTAssertFalse(selectVoiceBody.contains("previewSelectedVoice"))
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
        let decoded = KeyboardShortcut(identifier: "control-option-shift-command-p")
        let plan = GlobalHotKeyRegistrationPlan.commandPalette(shortcut: decoded)

        XCTAssertEqual(decoded.identifier, "control-option-shift-command-p")
        XCTAssertEqual(decoded.displayName, "Control + Option + Shift + Command + P")
        XCTAssertEqual(plan.keyCode, UInt32(kVK_ANSI_P))
        XCTAssertEqual(plan.modifiers, UInt32(cmdKey | optionKey | controlKey | shiftKey))
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
        let result = KeyboardShortcut.recording(
            keyCode: UInt32(kVK_ANSI_V),
            modifierFlags: [.control, .option, .command]
        )

        guard case .invalid(let message) = result else {
            return XCTFail("Expected Control + Option + Command + V to be rejected")
        }
        XCTAssertTrue(message.contains("reserved"))
    }

    func testShortcutRecordingAcceptsArbitraryValidCombo() throws {
        let result = KeyboardShortcut.recording(
            keyCode: UInt32(kVK_ANSI_Y),
            modifierFlags: [.control, .shift, .command]
        )

        guard case .valid(let shortcut) = result else {
            return XCTFail("Expected custom shortcut to be accepted")
        }
        XCTAssertEqual(shortcut.identifier, "control-shift-command-y")
        XCTAssertEqual(shortcut.displayName, "Control + Shift + Command + Y")
    }

    func testShortcutRecordingRejectsInvalidCombosWithoutSilentFallback() throws {
        let result = KeyboardShortcut.recording(
            keyCode: UInt32(kVK_ANSI_Y),
            modifierFlags: [.command]
        )

        guard case .invalid(let message) = result else {
            return XCTFail("Expected Command-only shortcut to be rejected")
        }
        XCTAssertTrue(message.contains("Include Control, Option, or Shift"))
    }

    func testShortcutRecordingSuspendsGlobalHotKeyRegistration() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("onShortcutRecordingChanged: { [weak self] isRecording in"))
        XCTAssertTrue(source.contains("self?.unregisterGlobalHotKeys()"))
        XCTAssertTrue(source.contains("self?.registerGlobalHotKeys()"))
        XCTAssertTrue(source.contains("setupShortcutRecorderButton.onRecordingChanged = { [weak self] isRecording in"))
        XCTAssertTrue(source.contains("onRecordingChanged?(true)"))
        XCTAssertTrue(source.contains("onRecordingChanged?(false)"))
    }
}
