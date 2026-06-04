import XCTest
@testable import Tri_State_Relay_Service

final class RelayCliTests: XCTestCase {
    override func tearDown() {
        unsetenv("TSRS_DB_PATH")
        super.tearDown()
    }

    func testVersionPrintsRelayVersion() {
        let result = runRelayCli(["--version"])

        XCTAssertEqual(result.stdout, "relay 0.1.0")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
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
        XCTAssertEqual(runRelayCli(["mute"]).stdout, "muted")
        XCTAssertEqual(runRelayCli(["ready"]).stdout, "release queued, but muted is on")
        XCTAssertEqual(runRelayCli(["unmute"]).stdout, "unmuted")
        XCTAssertEqual(runRelayCli(["focus"]).stdout, "focus mode on")

        _ = runRelayCli(["--line", "Brain", "--message", "clear me"])
        XCTAssertEqual(runRelayCli(["clear"]).stdout, "cleared 1 relays")
        XCTAssertEqual(runRelayCli(["list"]).stdout, "mode=focus muted=false")
    }

    func testStatusReportsJsonForQueue() throws {
        setenv("TSRS_DB_PATH", isolatedDatabasePath(), 1)
        _ = runRelayCli(["--line", "Brain", "--message", "json please"])

        let result = runRelayCli(["status"])
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)

        let object = try jsonObject(result.stdout)
        XCTAssertEqual(object["profile"] as? String, "direct")
        XCTAssertEqual(object["mode"] as? String, "focus")
        XCTAssertEqual(object["queueCount"] as? Int, 1)

        let counts = try XCTUnwrap(object["counts"] as? [String: Int])
        XCTAssertEqual(counts["queued"], 1)
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

private func jsonObject(_ text: String) throws -> [String: Any] {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
