import XCTest

final class MessageValidationTests: XCTestCase {
    func testSwiftValidationPortIsStillExplicitlyMissing() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertFalse(source.contains("RelayValidator"))
        XCTAssertFalse(source.contains("token=ghp_"))
    }
}
