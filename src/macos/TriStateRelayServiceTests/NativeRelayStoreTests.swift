import XCTest
@testable import Tri_State_Relay_Service

final class NativeRelayStoreTests: XCTestCase {
    func testFreshDatabaseDefaultSettings() throws {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databasePath = missingDirectory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
        }
        
        let store = NativeRelayStore(profile: "direct")
        
        let settings = store.loadSettings()
        XCTAssertEqual(settings.inactiveLineCombinerCommand, "")
        
        let status = store.loadStatus()
        XCTAssertEqual(status.mode, "focus")
        XCTAssertEqual(status.muted, false)
        XCTAssertEqual(status.queued, 0)
    }
}
