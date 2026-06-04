import XCTest

final class PlaybackProfileTests: XCTestCase {
    func testSpeechPlaybackIsProfileGated() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertTrue(source.contains("#if APP_STORE\n        let utterance = AVSpeechUtterance(string: claim.text)"))
        XCTAssertTrue(source.contains("#else\n        let option = speechVoiceOption(identifier: model.loadSettings().speechVoiceIdentifier)"))
        XCTAssertTrue(source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/say\")"))
    }

    func testRelayProcessorIsNotReferencedByAppBundleCode() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertFalse(source.contains("relay-processor"))
    }

    func testOnlyPlayNextGlobalHotKeyIsRegistered() throws {
        let source = try triStateRelayServiceSource()
        XCTAssertTrue(source.contains("Control-Option-Command-Space"))
        XCTAssertTrue(source.contains("kVK_Space"))
        XCTAssertFalse(source.contains("Control-Option-Command-V"))
        XCTAssertFalse(source.contains("kVK_ANSI_V"))
    }
}
