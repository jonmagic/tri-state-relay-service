import XCTest
@testable import Tri_State_Relay_Service

final class RelayCliTests: XCTestCase {
    override func tearDown() {
        unsetenv("TSRS_DB_PATH")
        unsetenv("TSRS_PROCESSOR_AUTH")
        super.tearDown()
    }

    func testVersionPrintsRelayVersion() {
        let result = runRelayCli(["--version"])

        XCTAssertEqual(result.stdout, "relay 1.1.2")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCliVersionMatchesAppBundleVersion() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let infoPlistURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)

        XCTAssertTrue(infoPlist.contains("<key>CFBundleShortVersionString</key>\n  <string>1.1.2</string>"))
        XCTAssertEqual(relayCliVersion, "1.1.2")
    }

    func testNoArgumentsPrintsUsage() {
        let result = runRelayCli([])

        XCTAssertTrue(result.stdout.contains("Usage: relay"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testNormalizeValidRelaySucceeds() {
        let result = runRelayCli([
            "normalize",
            "--line", "  Brain\nStatus  ",
            "--message", "  The   build passed.  ",
        ])

        XCTAssertEqual(result.stdout, "normalized Brain Status: The build passed. (type=update priority=normal)")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testNormalizeMissingMessageFails() {
        let result = runRelayCli([
            "normalize",
            "--line", "Brain",
        ])

        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "message is required")
        XCTAssertEqual(result.exitCode, 1)
    }

    func testNormalizeRejectsUnknownFlag() {
        let result = runRelayCli([
            "normalize",
            "--line", "Brain",
            "--message", "hi",
            "--bogus", "x",
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("unknown flag: --bogus"))
    }

    func testUnknownCommandFailsWithUsage() {
        let result = runRelayCli(["frobnicate"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("unknown command: frobnicate"))
        XCTAssertTrue(result.stderr.contains("Usage: relay"))
    }

    func testEnqueueListAndStateUseIsolatedDatabase() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        let enqueue = runRelayCli([
            "--line", " Brain ",
            "--message", " hello   world ",
            "--type", "complete",
            "--priority", "high",
            "--session", "session-1",
            "--app", "Copilot",
        ])

        XCTAssertEqual(enqueue.stdout, "queued relay #1 Brain: hello world")
        XCTAssertEqual(enqueue.stderr, "")
        XCTAssertEqual(enqueue.exitCode, 0)

        let list = runRelayCli(["list"])
        XCTAssertEqual(list.stdout, "mode=focus muted=false\n#1 [queued] [high] Brain: hello world")
        XCTAssertEqual(list.exitCode, 0)

        let state = runRelayCli(["state"])
        XCTAssertEqual(state.stdout, "focus, active-line=Brain, inactive-line-combiner=none")
        XCTAssertEqual(state.exitCode, 0)
    }

    func testModeMuteAndClearCommandsUseDatabase() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        XCTAssertEqual(runRelayCli(["ready"]).stdout, "ready to release one relay")
        XCTAssertEqual(runRelayCli(["state"]).stdout, "ready, active-line=none, inactive-line-combiner=none")
        XCTAssertEqual(runRelayCli(["live"]).stdout, "live mode on")
        XCTAssertEqual(runRelayCli(["state"]).stdout, "live, active-line=none, inactive-line-combiner=none")
        XCTAssertEqual(runRelayCli(["mute"]).stdout, "muted")
        XCTAssertEqual(runRelayCli(["live"]).stdout, "live mode on, but muted is on")
        XCTAssertEqual(runRelayCli(["unmute"]).stdout, "unmuted")
        XCTAssertEqual(runRelayCli(["focus"]).stdout, "focus mode on")

        _ = runRelayCli(["--line", "Brain", "--message", "clear me"])
        XCTAssertEqual(runRelayCli(["clear"]).stdout, "cleared 1 relays")
        XCTAssertEqual(runRelayCli(["list"]).stdout, "mode=focus muted=false")
    }

    func testMutatingCommandsPostQueueWakeNotifications() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        let wakes = WakeCounter()

        XCTAssertEqual(runRelayCli(["status"], wakeNotifier: wakes.notifier).exitCode, 0)
        XCTAssertEqual(wakes.count, 0)

        XCTAssertEqual(runRelayCli(["--line", "Brain", "--message", "wake me"], wakeNotifier: wakes.notifier).exitCode, 0)
        XCTAssertEqual(wakes.count, 1)

        XCTAssertEqual(runRelayCli(["ready"], wakeNotifier: wakes.notifier).stdout, "ready to release one relay")
        XCTAssertEqual(wakes.count, 2)

        XCTAssertEqual(runRelayCli(["debug", "wake"], wakeNotifier: wakes.notifier).stdout, "posted queue wake notification")
        XCTAssertEqual(wakes.count, 3)

        XCTAssertEqual(runRelayCli(["clear-delivered"], wakeNotifier: wakes.notifier).stdout, "cleared 0 delivered relays")
        XCTAssertEqual(wakes.count, 3)
    }

    func testStatusReportsJsonForQueue() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        _ = runRelayCli(["--line", "Brain", "--message", "json please", "--session", "sess-1", "--app", "Copilot"])

        let result = runRelayCli(["status"])
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)

        let object = try jsonObject(result.stdout)
        XCTAssertEqual(object["profile"] as? String, "direct")
        XCTAssertEqual(object["mode"] as? String, "focus")
        XCTAssertEqual(object["queueCount"] as? Int, 1)
        XCTAssertNotNil(object["inactiveLineCombinerCommand"] as? String)
        XCTAssertNotNil(object["speechCommand"] as? String)
        XCTAssertNotNil(object["voiceCommand"] as? String)

        let counts = try XCTUnwrap(object["counts"] as? [String: Int])
        XCTAssertEqual(counts["queued"], 1)

        let overview = try XCTUnwrap(object["overview"] as? [String: Any])
        let byPriority = try XCTUnwrap(overview["byPriority"] as? [[String: Any]])
        XCTAssertEqual(byPriority.first?["priority"] as? String, "normal")
        XCTAssertEqual(byPriority.first?["count"] as? Int, 1)

        let capabilities = try XCTUnwrap(object["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["terminalEnqueue"] as? Bool, true)
        XCTAssertEqual(capabilities["nativeSpeech"] as? Bool, false)

        let lineSources = try XCTUnwrap(object["lineSources"] as? [String: Any])
        let brainSource = try XCTUnwrap(lineSources["Brain"] as? [String: Any])
        XCTAssertEqual(brainSource["session"] as? String, "sess-1")
        XCTAssertEqual(brainSource["app"] as? String, "Copilot")
    }

    func testSettingsPersistsSpeechCommand() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        let updated = try jsonObject(runRelayCli(["settings", "--speech-command", "/usr/bin/say -v Samantha <message>"]).stdout)
        XCTAssertEqual(updated["speechCommand"] as? String, "/usr/bin/say -v Samantha <message>")

        let reread = try jsonObject(runRelayCli(["settings"]).stdout)
        XCTAssertEqual(reread["speechCommand"] as? String, "/usr/bin/say -v Samantha <message>")
    }

    func testSettingsPersistsVoiceCommand() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        let command = "/usr/bin/say -v <voice-id> -f <text-file> -o <output-file>"
        let updated = try jsonObject(runRelayCli(["settings", "--voice-command", command]).stdout)
        XCTAssertEqual(updated["voiceCommand"] as? String, command)

        let reread = try jsonObject(runRelayCli(["settings"]).stdout)
        XCTAssertEqual(reread["voiceCommand"] as? String, command)

        let reset = try jsonObject(runRelayCli(["settings", "--voice-command", "none"]).stdout)
        XCTAssertTrue((reset["voiceCommand"] as? String)?.contains("Voice command.") == true)
    }

    func testFirstStartCommandResetsOnlySetupCompletion() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        _ = runRelayCli(["--line", "Brain", "--message", "preserve me"])
        _ = runRelayCli(["first-start", "complete"])
        XCTAssertEqual(runRelayCli(["first-start"]).stdout, "complete")

        let reset = runRelayCli(["first-start", "reset"])
        XCTAssertEqual(reset.stdout, "first-start setup reset to needs-setup")
        XCTAssertEqual(reset.exitCode, 0)
        XCTAssertEqual(runRelayCli(["first-start", "status"]).stdout, "needs-setup")
        XCTAssertTrue(runRelayCli(["list"]).stdout.contains("Brain: preserve me"))

        XCTAssertEqual(runRelayCli(["first-start", "complete"]).stdout, "first-start setup marked complete")
        XCTAssertEqual(runRelayCli(["first-start", "status"]).stdout, "complete")
    }

    func testFreshDatabaseFirstStartDefaultsToNeedsSetup() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        XCTAssertEqual(runRelayCli(["first-start", "status"]).stdout, "needs-setup")
        XCTAssertEqual(runRelayCli(["state"]).stdout, "focus, active-line=none, inactive-line-combiner=none")
    }

    func testFirstStartDevResetDatabaseRequiresConfirmationAndClearsData() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        _ = runRelayCli(["--line", "Brain", "--message", "delete me"])
        _ = runRelayCli(["first-start", "complete"])
        XCTAssertTrue(runRelayCli(["list"]).stdout.contains("Brain: delete me"))

        let unconfirmed = runRelayCli(["first-start", "dev-reset-database"])
        XCTAssertEqual(unconfirmed.exitCode, 1)
        XCTAssertTrue(unconfirmed.stderr.contains("requires --confirm"))
        XCTAssertTrue(runRelayCli(["list"]).stdout.contains("Brain: delete me"))

        let reset = runRelayCli(["first-start", "dev-reset-database", "--confirm"])
        XCTAssertEqual(reset.stdout, "fresh database recreated, first-start needs-setup")
        XCTAssertEqual(reset.exitCode, 0)
        XCTAssertEqual(runRelayCli(["list"]).stdout, "mode=focus muted=false")
        XCTAssertEqual(runRelayCli(["first-start", "status"]).stdout, "needs-setup")
    }

    func testInactiveLineEnqueueKeepsLatestOnly() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        _ = runRelayCli(["line", "Brain"])
        _ = runRelayCli(["--line", "Other", "--message", "first inactive"])
        _ = runRelayCli(["--line", "Other", "--message", "second inactive"])

        let list = runRelayCli(["list"]).stdout
        XCTAssertTrue(list.contains("Other: second inactive"))
        XCTAssertFalse(list.contains("first inactive"))
    }

    func testConfiguredInactiveLineCombinerReplacesPendingDigest() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        let script = try inactiveCombinerScript(outputMessage: "Other summary: setup issue is isolated to the old CLI path.")

        _ = runRelayCli(["line", "Brain"])
        XCTAssertEqual(runRelayCli(["combiner", "--command", "\(script) <input> <system>"]).stdout, "inactive line combiner set to custom")
        _ = runRelayCli(["--line", "Other", "--message", "first inactive"])
        _ = runRelayCli(["--line", "Other", "--message", "second inactive"])

        let list = runRelayCli(["list"]).stdout
        XCTAssertTrue(list.contains("Other summary: setup issue is isolated to the old CLI path."))
        XCTAssertFalse(list.contains("first inactive"))
        XCTAssertFalse(list.contains("second inactive"))
    }

    func testInactiveLineCombinerDoesNotExpandPlaceholdersInsideInput() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        let script = try inactiveCombinerScript(outputMessage: "Other summary: placeholder text stayed inside input.", rejectSystemPromptInInput: true)

        _ = runRelayCli(["line", "Brain"])
        _ = runRelayCli(["combiner", "--command", "\(script) <input>"])
        let result = runRelayCli(["--line", "Other", "--message", "literal <system> marker"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(runRelayCli(["list"]).stdout.contains("Other summary: placeholder text stayed inside input."))
    }

    func testLiveModePreservesInactiveMessagesAndRotatesLineBatches() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        setenv("TSRS_PROCESSOR_AUTH", "app-owned-processor", 1)
        defer { unsetenv("TSRS_PROCESSOR_AUTH") }

        _ = runRelayCli(["line", "Brain"])
        _ = runRelayCli(["live"])
        _ = runRelayCli(["--line", "Other", "--message", "other one"])
        _ = runRelayCli(["--line", "Other", "--message", "other two"])
        _ = runRelayCli(["--line", "API", "--message", "api one"])

        var claim = try jsonObject(runRelayCli(["app-claim-next"]).stdout)
        let otherOneId = try XCTUnwrap(claim["id"] as? Int)
        XCTAssertEqual(claim["line"] as? String, "Other")
        XCTAssertEqual(claim["text"] as? String, "Other. other one")
        _ = runRelayCli(["app-mark-heard", "--id", String(otherOneId)])

        _ = runRelayCli(["--line", "Other", "--message", "other three"])

        claim = try jsonObject(runRelayCli(["app-claim-next"]).stdout)
        let otherTwoId = try XCTUnwrap(claim["id"] as? Int)
        XCTAssertEqual(claim["line"] as? String, "Other")
        XCTAssertEqual(claim["text"] as? String, "other two")
        _ = runRelayCli(["app-mark-heard", "--id", String(otherTwoId)])

        claim = try jsonObject(runRelayCli(["app-claim-next"]).stdout)
        let apiId = try XCTUnwrap(claim["id"] as? Int)
        XCTAssertEqual(claim["line"] as? String, "API")
        XCTAssertEqual(claim["text"] as? String, "API. api one")
        _ = runRelayCli(["app-mark-heard", "--id", String(apiId)])

        claim = try jsonObject(runRelayCli(["app-claim-next"]).stdout)
        XCTAssertEqual(claim["line"] as? String, "Other")
        XCTAssertEqual(claim["text"] as? String, "Other. other three")
        XCTAssertEqual(runRelayCli(["state"]).stdout, "live, active-line=Other, inactive-line-combiner=none")
    }

    func testAppClaimNextRequiresAuthorization() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        unsetenv("TSRS_PROCESSOR_AUTH")

        let result = runRelayCli(["app-claim-next"])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("app authorization"))
    }

    func testAppClaimNextMarkHeardAndFailedFlow() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        setenv("TSRS_PROCESSOR_AUTH", "app-owned-processor", 1)
        defer { unsetenv("TSRS_PROCESSOR_AUTH") }

        _ = runRelayCli(["--line", "Brain", "--message", "hello relay"])
        _ = runRelayCli(["ready"])

        let claim = runRelayCli(["app-claim-next"])
        XCTAssertEqual(claim.exitCode, 0)
        let claimed = try jsonObject(claim.stdout)
        let id = try XCTUnwrap(claimed["id"] as? Int)
        XCTAssertEqual(claimed["line"] as? String, "Brain")
        XCTAssertEqual(claimed["text"] as? String, "Brain. hello relay")

        // Active-line claim bypasses ready mode and leaves it untouched.
        XCTAssertEqual(runRelayCli(["state"]).stdout, "ready, active-line=Brain, inactive-line-combiner=none")

        let heard = runRelayCli(["app-mark-heard", "--id", String(id)])
        XCTAssertEqual(heard.stdout, "heard #\(id)")
        XCTAssertEqual(heard.exitCode, 0)

        let status = try jsonObject(runRelayCli(["status"]).stdout)
        let counts = try XCTUnwrap(status["counts"] as? [String: Int])
        XCTAssertEqual(counts["heard"], 1)
        XCTAssertEqual(counts["speaking"], 0)
        let spokenUsage = try XCTUnwrap(status["spokenUsage"] as? [String: Any])
        XCTAssertEqual(spokenUsage["relays"] as? Int, 1)
        XCTAssertEqual(spokenUsage["characters"] as? Int, 18)

        let failed = runRelayCli(["app-mark-failed", "--id", String(id)])
        XCTAssertEqual(failed.stdout, "failed #\(id)")
    }

    func testAppClaimNextOmitsLinePrefixWhenRecentlySpoken() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        setenv("TSRS_PROCESSOR_AUTH", "app-owned-processor", 1)
        defer { unsetenv("TSRS_PROCESSOR_AUTH") }

        _ = runRelayCli(["--line", "Brain", "--message", "first"])
        _ = runRelayCli(["--line", "Brain", "--message", "second"])
        _ = runRelayCli(["ready"])

        let firstClaim = try jsonObject(runRelayCli(["app-claim-next", "--line", "Brain"]).stdout)
        let firstId = try XCTUnwrap(firstClaim["id"] as? Int)
        XCTAssertEqual(firstClaim["text"] as? String, "Brain. first")
        _ = runRelayCli(["app-mark-heard", "--id", String(firstId)])

        let secondClaim = try jsonObject(runRelayCli(["app-claim-next", "--line", "Brain"]).stdout)
        XCTAssertEqual(secondClaim["text"] as? String, "second")
    }

    func testAppClaimNextReturnsNullWhenNothingEligible() {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        setenv("TSRS_PROCESSOR_AUTH", "app-owned-processor", 1)
        defer { unsetenv("TSRS_PROCESSOR_AUTH") }

        let result = runRelayCli(["app-claim-next"])
        XCTAssertEqual(result.stdout, "null")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testGlobalReadyClaimResetsModeToFocus() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        setenv("TSRS_PROCESSOR_AUTH", "app-owned-processor", 1)
        defer { unsetenv("TSRS_PROCESSOR_AUTH") }

        // Active line has no queued relays, so claiming uses the global ready path.
        _ = runRelayCli(["line", "Idle"])
        _ = runRelayCli(["--line", "Brain", "--message", "global claim"])
        _ = runRelayCli(["ready"])

        let claim = try jsonObject(runRelayCli(["app-claim-next"]).stdout)
        XCTAssertEqual(claim["line"] as? String, "Brain")
        XCTAssertEqual(runRelayCli(["state"]).stdout, "focus, active-line=Idle, inactive-line-combiner=none")
    }

    func testCliStatusAndInstallCliUseSourceAndTargetFlags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("relay-source").path
        let target = directory.appendingPathComponent("bin/relay").path
        try "#!/usr/bin/env sh\necho relay 0.1.0\n".write(toFile: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)

        let missing = runRelayCli(["cli-status", "--source", source, "--target", target])
        XCTAssertEqual(try jsonObject(missing.stdout)["status"] as? String, "missing")

        let installed = runRelayCli(["install-cli", "--source", source, "--target", target])
        XCTAssertEqual(try jsonObject(installed.stdout)["status"] as? String, "current")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target))

        let current = runRelayCli(["cli-status", "--source", source, "--target", target])
        XCTAssertEqual(try jsonObject(current.stdout)["status"] as? String, "current")
    }

    func testCliStatusDefaultsToUsrLocalBinRelay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("relay-source").path
        try "#!/usr/bin/env sh\necho relay 0.1.0\n".write(toFile: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)
        unsetenv("TSRS_RELAY_INSTALL_TARGET")

        let status = try jsonObject(runRelayCli(["cli-status", "--source", source]).stdout)

        XCTAssertEqual(status["targetPath"] as? String, "/usr/local/bin/relay")
    }

    func testLineCombinerSettingsAndLifecycleCommands() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)

        XCTAssertEqual(runRelayCli(["line"]).stdout, "none")
        XCTAssertEqual(runRelayCli(["line", "Brain"]).stdout, "active line set to Brain")
        XCTAssertEqual(runRelayCli(["line"]).stdout, "Brain")

        XCTAssertTrue(runRelayCli(["combiner"]).stdout.contains("Inactive line combiner command."))
        XCTAssertEqual(runRelayCli(["combiner", "--command", "llm prompt <input>"]).stdout, "inactive line combiner set to custom")
        XCTAssertEqual(runRelayCli(["state"]).stdout, "focus, active-line=Brain, inactive-line-combiner=custom")

        let settings = try jsonObject(runRelayCli(["settings"]).stdout)
        XCTAssertEqual(settings["inactiveLineCombiner"] as? String, "custom")
        XCTAssertEqual(settings["inactiveLineCombinerCommand"] as? String, "llm prompt <input>")

        _ = runRelayCli(["--line", "Brain", "--message", "first"])
        _ = runRelayCli(["--line", "Brain", "--message", "second"])
        XCTAssertEqual(runRelayCli(["skip-next"]).stdout, "skipped relay #1")
        XCTAssertEqual(runRelayCli(["clear-line", "--line", "Brain"]).stdout, "cleared 1 queued relays from Brain")
        XCTAssertEqual(runRelayCli(["clear-delivered"]).stdout, "cleared 0 delivered relays")
        XCTAssertEqual(runRelayCli(["acknowledge"]).stdout, "no delivered relay to mark handled")
        XCTAssertEqual(runRelayCli(["replay-last"]).stdout, "no delivered relay to replay")
    }
}

private func isolatedDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("relay.db")
        .path
}

private final class WakeCounter {
    private(set) var count = 0

    var notifier: RelayWakeNotifier {
        RelayWakeNotifier { [weak self] in
            self?.count += 1
        }
    }
}

private func jsonObject(_ text: String) throws -> [String: Any] {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func inactiveCombinerScript(outputMessage: String, rejectSystemPromptInInput: Bool = false) throws -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tsrs-combiner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("combiner").path
    let escapedMessage = outputMessage.replacingOccurrences(of: "'", with: "'\\''")
    let guardSystemPrompt = rejectSystemPromptInInput ? "case \"$1\" in *'You compose one useful relay'*) exit 7 ;; esac\n" : ""
    let body = """
    #!/bin/sh
    \(guardSystemPrompt)\
    printf '%s\\n' '{"action":"replace","type":"update","priority":"normal","message":"\(escapedMessage)"}'
    """
    try body.write(toFile: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
    return script
}
