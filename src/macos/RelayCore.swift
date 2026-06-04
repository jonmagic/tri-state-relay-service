import Foundation

// UI-free relay core shared by the macOS app target and the native `relay`
// command-line target. This file must not import AppKit, AVFoundation, or any
// macOS UI/audio frameworks so it can compile into a plain command-line tool.

let relayCliVersion = "0.1.0"

let relayMessageTypes = ["update", "complete", "blocked", "needs-input"]
let relayPriorities = ["low", "normal", "high"]

struct NewRelayInput {
    let line: String?
    let message: String
    let type: String?
    let priority: String?
    let session: String?
    let app: String?
    let cwd: String?
    let url: String?
}

struct NormalizedRelay {
    let line: String
    let message: String
    let type: String
    let priority: String
    let session: String?
    let app: String?
    let cwd: String?
    let url: String?
}

enum RelayValidationError: LocalizedError, Equatable {
    case required(String)
    case tooLong(String, Int)
    case invalidEnum(String, [String])
    case unsafeMessage

    var errorDescription: String? {
        switch self {
        case .required(let field):
            return "\(field) is required"
        case .tooLong(let field, let maxLength):
            if field == "optional metadata" {
                return "optional metadata must be \(maxLength) characters or fewer"
            }

            return "\(field) must be \(maxLength) characters or fewer"
        case .invalidEnum(let field, let allowed):
            return "\(field) must be one of: \(allowed.joined(separator: ", "))"
        case .unsafeMessage:
            return "message looks like it may contain a secret or token"
        }
    }
}

func normalizeRelay(_ input: NewRelayInput) throws -> NormalizedRelay {
    let line = try normalizeRequiredRelayText(input.line ?? "", field: "line", maxLength: 80)
    let message = try normalizeRequiredRelayText(input.message, field: "message", maxLength: 240)
    let type = try normalizeRelayEnum(input.type ?? "update", allowed: relayMessageTypes, field: "type")
    let priority = try normalizeRelayEnum(input.priority ?? "normal", allowed: relayPriorities, field: "priority")
    let session = try normalizeOptionalRelayText(input.session, maxLength: 120)
    let app = try normalizeOptionalRelayText(input.app, maxLength: 80)
    let cwd = try normalizeOptionalRelayText(input.cwd, maxLength: 500)
    let url = try normalizeOptionalRelayText(input.url, maxLength: 500)

    try rejectUnsafeRelayMessage(message)

    return NormalizedRelay(
        line: line,
        message: message,
        type: type,
        priority: priority,
        session: session,
        app: app,
        cwd: cwd,
        url: url
    )
}

private func normalizeRequiredRelayText(_ value: String, field: String, maxLength: Int) throws -> String {
    let normalized = normalizeRelayWhitespace(value)

    if normalized.isEmpty {
        throw RelayValidationError.required(field)
    }

    if normalized.count > maxLength {
        throw RelayValidationError.tooLong(field, maxLength)
    }

    return normalized
}

private func normalizeOptionalRelayText(_ value: String?, maxLength: Int) throws -> String? {
    guard let value else {
        return nil
    }

    let normalized = normalizeRelayWhitespace(value)

    if normalized.isEmpty {
        return nil
    }

    if normalized.count > maxLength {
        throw RelayValidationError.tooLong("optional metadata", maxLength)
    }

    return normalized
}

private func normalizeRelayEnum(_ value: String, allowed: [String], field: String) throws -> String {
    if allowed.contains(value) {
        return value
    }

    throw RelayValidationError.invalidEnum(field, allowed)
}

private func normalizeRelayWhitespace(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func rejectUnsafeRelayMessage(_ message: String) throws {
    let patterns = [
        #"gh[pousr]_[A-Za-z0-9_]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"(?i)(?:api[_-]?key|token|secret)\s*[:=]\s*\S{8,}"#,
        #"[A-Za-z0-9+/]{32,}={0,2}"#,
    ]

    for pattern in patterns {
        if message.range(of: pattern, options: .regularExpression) != nil {
            throw RelayValidationError.unsafeMessage
        }
    }
}

// MARK: - Native CLI dispatcher

struct RelayCliResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

let relayCliUsage = """
Usage: relay <command> [options]

Commands:
  normalize --line <line> --message <message> [--type <type>] [--priority <priority>]
            [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]
                       Validate and normalize a relay without writing to the queue.
  --version            Print the CLI version.
  help                 Print this help.

This native target is an in-progress Swift replacement for the Perry-built
`relay` CLI. Queue-writing commands are not implemented here yet; see
docs/cli-parity-inventory.md for the remaining parity gaps.
"""

// Pure argument dispatcher so behavior is testable without a process boundary.
func runRelayCli(_ arguments: [String], version: String = relayCliVersion) -> RelayCliResult {
    guard let command = arguments.first else {
        return RelayCliResult(stdout: relayCliUsage, stderr: "", exitCode: 0)
    }

    switch command {
    case "--version", "version":
        return RelayCliResult(stdout: "relay \(version)", stderr: "", exitCode: 0)
    case "help", "--help", "-h":
        return RelayCliResult(stdout: relayCliUsage, stderr: "", exitCode: 0)
    case "normalize":
        return runNormalizeCommand(Array(arguments.dropFirst()))
    default:
        return RelayCliResult(stdout: "", stderr: "unknown command: \(command)\n\(relayCliUsage)", exitCode: 1)
    }
}

private func runNormalizeCommand(_ arguments: [String]) -> RelayCliResult {
    let flags: [String: String]

    do {
        flags = try parseRelayFlags(arguments)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }

    let input = NewRelayInput(
        line: flags["line"],
        message: flags["message"] ?? "",
        type: flags["type"],
        priority: flags["priority"],
        session: flags["session"],
        app: flags["app"],
        cwd: flags["cwd"],
        url: flags["url"]
    )

    do {
        let relay = try normalizeRelay(input)
        let stdout = "normalized \(relay.line): \(relay.message) (type=\(relay.type) priority=\(relay.priority))"
        return RelayCliResult(stdout: stdout, stderr: "", exitCode: 0)
    } catch let error as RelayValidationError {
        return RelayCliResult(stdout: "", stderr: error.errorDescription ?? "invalid relay", exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private struct RelayCliFlagError: Error {
    let message: String
}

private let relayCliKnownFlags: Set<String> = [
    "line", "message", "type", "priority", "session", "app", "cwd", "url",
]

private func parseRelayFlags(_ arguments: [String]) throws -> [String: String] {
    var flags: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let token = arguments[index]

        guard token.hasPrefix("--") else {
            throw RelayCliFlagError(message: "unexpected argument: \(token)")
        }

        let name = String(token.dropFirst(2))

        guard relayCliKnownFlags.contains(name) else {
            throw RelayCliFlagError(message: "unknown flag: \(token)")
        }

        guard index + 1 < arguments.count else {
            throw RelayCliFlagError(message: "missing value for \(token)")
        }

        flags[name] = arguments[index + 1]
        index += 2
    }

    return flags
}
