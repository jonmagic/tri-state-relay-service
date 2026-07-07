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
                ["<app-bin>/speechify", "-v", "<voice-id>", "-f", "<text-file>", "-o", "<output-file>"],
                textFile: "/tmp/relay.txt",
                outputFile: "/tmp/relay.aiff",
                voiceID: "Samantha",
                appBin: "/Applications/TSRS.app/Contents/MacOS"
            ),
            ["/Applications/TSRS.app/Contents/MacOS/speechify", "-v", "Samantha", "-f", "/tmp/relay.txt", "-o", "/tmp/relay.aiff"]
        )
    }

    func testResolvedVoiceIdentifierUsesLineMappingThenProviderDefaultThenSelectedVoice() {
        let config = RelayConfig(
            voiceCommand: "<app-bin>/speechify --voice-id <voice-id> --text-file <text-file> --output-file <output-file>",
            voiceProvider: "speechify",
            voiceVariables: [:],
            voiceProviders: [
                "speechify": RelayVoiceProviderConfig(
                    defaultVoiceId: "george",
                    autoAssignLineVoices: false,
                    catalogCommand: nil,
                    assignmentStrategy: defaultLineVoiceAssignmentStrategy,
                    lineVoices: ["Brain": "henry"]
                )
            ],
            combinerCommand: "",
            combinerVariables: [:],
            cleanupRetentionMinutes: defaultCleanupRetentionMinutes
        )

        XCTAssertEqual(resolvedVoiceIdentifier(for: "Brain", config: config, selectedVoice: "System Default"), "henry")
        XCTAssertEqual(resolvedVoiceIdentifier(for: "Work", config: config, selectedVoice: "System Default"), "george")

        var noProvider = config
        noProvider.voiceProvider = nil
        XCTAssertEqual(resolvedVoiceIdentifier(for: "Brain", config: noProvider, selectedVoice: "System Default"), "System Default")
    }

    func testAutoAssignLineVoicePersistsStickyMapping() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let configPath = directory.appendingPathComponent("config.toml").path
        try """
        [voice]
        provider = "speechify"
        command = "<app-bin>/speechify --text-file <text-file> --output-file <output-file> --voice-id <voice-id>"
        [speechify]
        default_voice_id = "george"
        auto_assign_line_voices = true
        catalog_command = "<app-bin>/speechify voices"
        assignment_strategy = "stable-hash"
        [speechify.line_voices]
        Brain = "george"
        [combiner]
        command = ""
        [retention]
        cleanup_retention_minutes = 60
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        let first = try autoAssignLineVoiceIfNeeded(
            line: "Work",
            configPath: configPath,
            appBin: "/Applications/TSRS.app/Contents/MacOS",
            catalogRunner: { command in
                XCTAssertEqual(command, ["/Applications/TSRS.app/Contents/MacOS/speechify", "voices"])
                return ["george", "henry", "simba"]
            }
        )
        XCTAssertNotNil(first)

        let afterFirst = try RelayConfig.loadExisting(path: configPath)
        XCTAssertEqual(afterFirst.voiceProviders["speechify"]?.lineVoices["Work"], first)

        let second = try autoAssignLineVoiceIfNeeded(
            line: "Work",
            configPath: configPath,
            appBin: "/Applications/TSRS.app/Contents/MacOS",
            catalogRunner: { _ in
                XCTFail("existing line mapping should skip catalog fetch")
                return ["simba", "henry", "george"]
            }
        )
        XCTAssertNil(second)
        XCTAssertEqual(resolvedVoiceIdentifier(for: "Work", config: afterFirst, selectedVoice: nil), first)
    }

    func testProviderMappingsAreInertWithoutVoicePlaceholder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let configPath = directory.appendingPathComponent("config.toml").path
        try """
        [voice]
        provider = "speechify"
        command = "<app-bin>/speechify --text-file <text-file> --output-file <output-file>"
        [speechify]
        default_voice_id = "george"
        auto_assign_line_voices = true
        catalog_command = "<app-bin>/speechify voices"
        [speechify.line_voices]
        Brain = "henry"
        [combiner]
        command = ""
        [retention]
        cleanup_retention_minutes = 60
        """.write(toFile: configPath, atomically: true, encoding: .utf8)

        let resolution = resolvedVoiceIdentifierForPlayback(
            line: "Brain",
            selectedVoice: "System Default",
            configPath: configPath,
            appBin: "/Applications/TSRS.app/Contents/MacOS",
            catalogRunner: { _ in
                XCTFail("catalog should not run without <voice-id>")
                return ["george", "henry"]
            }
        )

        XCTAssertEqual(resolution.voiceIdentifier, "System Default")
    }

    func testVoiceCommandFailuresRecordDiagnosticsAndFallbackToSay() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("handleVoiceCommandFailure(message, text: fallbackText"))
        XCTAssertTrue(source.contains("model.recordVoiceCommandError(redactedVoiceCommandError(message))"))
        XCTAssertTrue(source.contains("redactedVoiceCommandError(message)"))
        XCTAssertTrue(source.contains("model.status.muted || inputCaptureSensor.isInputCaptureActive()"))
        XCTAssertTrue(source.contains("speakWithSay(text: text, option: option, claimId: claimId"))
        XCTAssertTrue(source.contains("Last BYO voice command error:"))
    }

    func testVoiceCommandPlaybackResolvesLineVoiceIdentifier() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("synthesizeVoiceCommand(text: claim.text, line: claim.line"))
        XCTAssertTrue(source.contains("resolvedVoiceIdentifierForPlayback(line: line"))
        XCTAssertTrue(source.contains("voiceID: resolution.voiceIdentifier"))
    }

    func testVoiceCommandOutputPathUsesCoreAudioFriendlyExtension() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("appendingPathComponent(\"relay.audio\")"))
        XCTAssertFalse(source.contains("appendingPathComponent(\"relay.mp3\")"))
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
