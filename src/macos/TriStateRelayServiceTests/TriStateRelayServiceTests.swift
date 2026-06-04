import XCTest
@testable import Tri_State_Relay_Service

final class TriStateRelayServiceTests: XCTestCase {
    func testDefaultStatusStartsFocused() throws {
        let store = NativeRelayStore(profile: "direct")
        let status = store.loadStatus()

        XCTAssertEqual(status.mode, "focus")
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
