import XCTest
@testable import Tri_State_Relay_Service

final class MessageValidationTests: XCTestCase {
    func testNormalizesRelayDefaultsAndWhitespace() throws {
        let relay = try normalizeRelay(NewRelayInput(
            line: "  Brain\nStatus  ",
            message: "  The   build\npassed.  ",
            type: nil,
            priority: nil,
            session: "  session-1  ",
            app: "  Copilot  ",
            cwd: "  /tmp/project  ",
            url: "  https://example.test  "
        ))

        XCTAssertEqual(relay.line, "Brain Status")
        XCTAssertEqual(relay.message, "The build passed.")
        XCTAssertEqual(relay.type, "update")
        XCTAssertEqual(relay.priority, "normal")
        XCTAssertEqual(relay.session, "session-1")
        XCTAssertEqual(relay.app, "Copilot")
        XCTAssertEqual(relay.cwd, "/tmp/project")
        XCTAssertEqual(relay.url, "https://example.test")
    }

    func testRejectsMissingRequiredFields() throws {
        XCTAssertThrowsError(try normalizeRelay(NewRelayInput(
            line: " ",
            message: "hello",
            type: nil,
            priority: nil,
            session: nil,
            app: nil,
            cwd: nil,
            url: nil
        ))) { error in
            XCTAssertEqual(error as? RelayValidationError, .required("line"))
        }

        XCTAssertThrowsError(try normalizeRelay(NewRelayInput(
            line: "Brain",
            message: " ",
            type: nil,
            priority: nil,
            session: nil,
            app: nil,
            cwd: nil,
            url: nil
        ))) { error in
            XCTAssertEqual(error as? RelayValidationError, .required("message"))
        }
    }

    func testRejectsInvalidTypeAndPriority() throws {
        XCTAssertThrowsError(try normalizeRelay(NewRelayInput(
            line: "Brain",
            message: "hello",
            type: "note",
            priority: nil,
            session: nil,
            app: nil,
            cwd: nil,
            url: nil
        ))) { error in
            XCTAssertEqual(error.localizedDescription, "type must be one of: update, complete, blocked, needs-input")
        }

        XCTAssertThrowsError(try normalizeRelay(NewRelayInput(
            line: "Brain",
            message: "hello",
            type: nil,
            priority: "urgent",
            session: nil,
            app: nil,
            cwd: nil,
            url: nil
        ))) { error in
            XCTAssertEqual(error.localizedDescription, "priority must be one of: low, normal, high")
        }
    }

    func testRejectsTokenLookingMessages() throws {
        let unsafeMessages = [
            "token=ghp_" + "abcdefghijklmnopqrstuvwxyz",
            "github_pat_abcdefghijklmnopqrstuvwxyz123456",
            "api_key: abcdefghijklmnop",
            "abcdefghijklmnopqrstuvwxyzABCDEF012345",
        ]

        for message in unsafeMessages {
            XCTAssertThrowsError(try normalizeRelay(NewRelayInput(
                line: "Brain",
                message: message,
                type: nil,
                priority: nil,
                session: nil,
                app: nil,
                cwd: nil,
                url: nil
            ))) { error in
                XCTAssertEqual(error as? RelayValidationError, .unsafeMessage)
            }
        }
    }
}
