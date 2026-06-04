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
}

private func isolatedDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("relay.db")
        .path
}
