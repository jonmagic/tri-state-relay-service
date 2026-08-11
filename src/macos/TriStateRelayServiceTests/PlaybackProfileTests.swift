import XCTest
import Carbon.HIToolbox
@testable import Tri_State_Relay_Service

final class PlaybackProfileTests: XCTestCase {
    func testOutputOnlySuperColliderDoesNotCountAsMicrophoneCapture() {
        XCTAssertTrue(isOutputOnlySuperColliderProcess(arguments: ["/Applications/SuperCollider.app/Contents/Resources/scsynth", "-i", "0", "-o", "2"]))
        XCTAssertTrue(isOutputOnlySuperColliderProcess(arguments: ["/usr/local/bin/scsynth", "-i0"]))
        XCTAssertFalse(isOutputOnlySuperColliderProcess(arguments: ["/usr/local/bin/scsynth", "-i", "2"]))
        XCTAssertFalse(isOutputOnlySuperColliderProcess(arguments: ["/usr/bin/other-audio", "-i", "0"]))
    }

    func testInputCapturePlaybackOverrideBypassesOnlyTheCaptureGate() {
        XCTAssertTrue(shouldPauseForInputCapture(isActive: true, allowsPlaybackDuringInputCapture: false))
        XCTAssertFalse(shouldPauseForInputCapture(isActive: true, allowsPlaybackDuringInputCapture: true))
        XCTAssertFalse(shouldPauseForInputCapture(isActive: false, allowsPlaybackDuringInputCapture: false))
    }

    func testStallDeadlineScalesWithMessageLength() {
        XCTAssertEqual(playbackStallMinimumTimeoutSeconds, 60)
        XCTAssertEqual(playbackStallTimeoutSeconds(forCharacterCount: 0), 60)
        XCTAssertEqual(playbackStallTimeoutSeconds(forCharacterCount: -10), 60)
        XCTAssertEqual(playbackStallTimeoutSeconds(forCharacterCount: 600), 160)
        XCTAssertEqual(playbackStallTimeoutSeconds(forCharacterCount: 1_200), 260)
    }

    func testHealthyLongPlaybackIsNotTreatedAsStalled() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var watch = PlaybackStallWatch()
        let timeout = playbackStallTimeoutSeconds(forCharacterCount: 600)

        XCTAssertFalse(watch.observe(isBusy: true, generation: 1, timeoutSeconds: timeout, now: start))
        XCTAssertFalse(watch.observe(isBusy: true, generation: 1, timeoutSeconds: timeout, now: start.addingTimeInterval(90)))
        XCTAssertFalse(watch.observe(isBusy: true, generation: 1, timeoutSeconds: timeout, now: start.addingTimeInterval(159)))
        XCTAssertTrue(watch.observe(isBusy: true, generation: 1, timeoutSeconds: timeout, now: start.addingTimeInterval(160)))
    }

    func testNewPlaybackGenerationResetsTheStallClock() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var watch = PlaybackStallWatch()

        XCTAssertFalse(watch.observe(isBusy: true, generation: 1, timeoutSeconds: 60, now: start))

        // A new attempt started without the watch ever observing an idle tick. It must not
        // inherit the previous attempt's deadline and be killed the moment it starts.
        XCTAssertFalse(watch.observe(isBusy: true, generation: 2, timeoutSeconds: 60, now: start.addingTimeInterval(600)))
        XCTAssertFalse(watch.observe(isBusy: true, generation: 2, timeoutSeconds: 60, now: start.addingTimeInterval(659)))
        XCTAssertTrue(watch.observe(isBusy: true, generation: 2, timeoutSeconds: 60, now: start.addingTimeInterval(660)))
    }

    func testIdlePlaybackClearsTheStallClock() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var watch = PlaybackStallWatch()

        XCTAssertFalse(watch.observe(isBusy: true, generation: 1, timeoutSeconds: 60, now: start))
        XCTAssertFalse(watch.observe(isBusy: false, generation: 1, timeoutSeconds: 60, now: start.addingTimeInterval(30)))
        XCTAssertFalse(watch.observe(isBusy: true, generation: 1, timeoutSeconds: 60, now: start.addingTimeInterval(600)))
        XCTAssertTrue(watch.observe(isBusy: true, generation: 1, timeoutSeconds: 60, now: start.addingTimeInterval(660)))
    }

    func testStallWatchBackfillsWhenPlaybackStartsWithoutTheWatchSeeingIt() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var watch = PlaybackStallWatch()

        XCTAssertFalse(watch.observe(isBusy: true, generation: 7, timeoutSeconds: 60, now: start))
        XCTAssertTrue(watch.observe(isBusy: true, generation: 7, timeoutSeconds: 60, now: start.addingTimeInterval(60)))
    }

    func testStalledPlaybackWaitsForTheOldProcessBeforeAdvancing() throws {
        let source = try triStateRelayServiceSource()

        // terminate() is asynchronous, so advancing immediately can overlap the next relay with
        // audio from the one being cancelled.
        XCTAssertTrue(source.contains("private func cancelActivePlayback(completion: (() -> Void)? = nil)"), source)
        XCTAssertTrue(source.contains("process.waitUntilExit()"), source)
        XCTAssertTrue(source.contains("self.playbackGeneration == cancelledGeneration"), source)
    }

    func testStalledPlaybackRecoveryIsWiredIntoTheSafetyTimer() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("func recoverIfStalled("))
        XCTAssertTrue(source.contains("nativePlayback.recoverIfStalled()"))
        XCTAssertTrue(source.contains("stallWatch.observe("))
    }

    func testStalledPlaybackRecoveryResetsEveryBusyComponent() throws {
        let source = try triStateRelayServiceSource()
        let recovery = try XCTUnwrap(source.range(of: "func cancelActivePlayback(").map { range in
            String(source[range.lowerBound...].prefix(2_000))
        })

        XCTAssertTrue(recovery.contains("terminate()"), recovery)
        XCTAssertTrue(recovery.contains("resolvingVoiceCommand = false"), recovery)
        XCTAssertTrue(recovery.contains("currentProcess = nil"), recovery)
        XCTAssertTrue(recovery.contains("currentAudioPlayer = nil"), recovery)
        XCTAssertTrue(recovery.contains("stopSpeaking(at: .immediate)"), recovery)
        XCTAssertTrue(recovery.contains("playbackGeneration += 1"), recovery)
    }

    func testEveryPlaybackCallbackVerifiesItsOwnIdentity() throws {
        let source = try triStateRelayServiceSource()

        // Recovery starts the next relay immediately, so a late callback from the killed
        // attempt must not mark or clear the relay that replaced it.
        XCTAssertTrue(source.contains("guard self.currentProcess === process else"), source)
        XCTAssertTrue(source.contains("guard currentProcess === process else"), source)
        XCTAssertTrue(source.contains("guard player === currentAudioPlayer else"), source)
        XCTAssertTrue(source.contains("guard utterance === currentUtterance else"), source)
    }

    func testClearingRelaysCancelsPlaybackInsteadOfLeavingAnOrphan() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("cancelActivePlaybackForClear()"), source)
    }

    func testClearDetectionUsesRowExistenceRatherThanSpeakingStatus() throws {
        let source = try triStateRelayServiceSource()

        // The stale-speaking sweep flips a still-playing relay to failed on its own 60s schedule,
        // so keying cancellation off status = 'speaking' would cancel healthy playback.
        XCTAssertTrue(source.contains("SELECT COUNT(*) FROM relays WHERE id = ?"), source)
        XCTAssertTrue(source.contains("func relayExists(id: Int) -> Bool"), source)
        XCTAssertFalse(source.contains("hasSpeakingRelay"), source)
    }

    func testReplayedMessagesAreCancellableByClear() throws {
        let source = try triStateRelayServiceSource()

        // A replay sets no claim, so without the row id a CLI clear cannot stop it.
        XCTAssertTrue(source.contains("func replayDeliveredMessage(_ text: String, id: Int? = nil)"), source)
        XCTAssertTrue(source.contains("currentId ?? currentReplayRelayId"), source)
    }

    func testEachPlaybackPhaseGetsItsOwnDeadline() throws {
        let source = try triStateRelayServiceSource()

        // Synthesis and playback are separate phases. Without a renewal the audio inherits
        // whatever budget a slow synthesis left behind and gets cut off early.
        XCTAssertTrue(source.contains("func renewPlaybackDeadline(seconds: TimeInterval)"), source)
        XCTAssertTrue(source.contains("renewPlaybackDeadline(seconds: player.duration + playbackStallMinimumTimeoutSeconds)"), source)
        XCTAssertTrue(source.contains("renewPlaybackDeadline(seconds: playbackStallTimeoutSeconds(forCharacterCount: text.count))"), source)
    }

    func testSpeechPlaybackIsProfileGated() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertTrue(source.contains("#if APP_STORE\n        let utterance = AVSpeechUtterance(string: claim.text)"))
        XCTAssertTrue(source.contains("if commandIsEnabled(settings.voiceCommand)"))
        XCTAssertTrue(source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/say\")"))
    }

    func testClaimPublishesPreparingBeforeGeneratedAudioSynthesis() throws {
        let source = try triStateRelayServiceSource()
        let preparing = try XCTUnwrap(source.range(of: "publishPlaybackObservation(relayId: claim.id, phase: .preparing)"))
        let synthesis = try XCTUnwrap(source.range(of: "synthesizeVoiceCommand(text: claim.text, line: claim.line"))

        XCTAssertLessThan(preparing.lowerBound, synthesis.lowerBound)
        XCTAssertFalse(String(source[preparing.lowerBound..<synthesis.lowerBound]).contains("phase: .playing"))
    }

    func testEveryProviderPublishesAudibleStartAndCompletion() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("try process.run()\n            publishPlayingIfClaimed(claimId)"), source)
        XCTAssertTrue(source.contains("if player.play() {\n                publishPlayingIfClaimed(claimId)\n            }"), source)
        XCTAssertTrue(source.contains("didStart utterance: AVSpeechUtterance"), source)
        XCTAssertTrue(source.contains("publishPlayingIfClaimed(currentId)"), source)
        XCTAssertTrue(source.contains("publishIdleIfClaimed(claimId, outcome: process.terminationStatus == 0 ? .heard : .failed)"), source)
        XCTAssertTrue(source.contains("publishIdleIfClaimed(id, outcome: .heard)"), source)
        XCTAssertTrue(source.contains("publishIdleIfClaimed(id, outcome: flag ? .heard : .failed)"), source)
    }

    func testCancellationFailureAndRequeueSettleIdle() throws {
        let source = try triStateRelayServiceSource()

        XCTAssertTrue(source.contains("publishIdleIfClaimed(cancelledId, outcome: .cancelled)"), source)
        XCTAssertTrue(source.contains("publishIdleIfClaimed(stalledId, outcome: .failed)"), source)
        XCTAssertTrue(source.contains("publishIdleIfClaimed(claimId, outcome: .requeued)"), source)
        XCTAssertTrue(source.contains("publishIdleIfClaimed(id, outcome: .failed)"), source)
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
        XCTAssertTrue(source.contains("model.status.muted || shouldPauseForInputCapture("))
        XCTAssertTrue(source.contains("allowsPlaybackDuringInputCapture: model.allowsInputCapturePlayback()"))
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
