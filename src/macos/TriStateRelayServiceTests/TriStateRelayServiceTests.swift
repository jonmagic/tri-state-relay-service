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
}

func triStateRelayServiceSource() throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TriStateRelayService.swift")

    return try String(contentsOf: sourceURL, encoding: .utf8)
}
