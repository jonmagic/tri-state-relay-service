import XCTest
@testable import Tri_State_Relay_Service

final class RelayCliTests: XCTestCase {
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
}
