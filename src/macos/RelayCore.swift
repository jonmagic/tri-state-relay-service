import Foundation
import SQLite3

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

let directRelayCapabilities: [String: Any] = [
    "profile": "direct",
    "nativeSpeech": false,
    "terminalEnqueue": true,
    "externalSpeechCommand": true,
    "externalInactiveLineCombiner": true,
    "lineSourceActions": true,
]

let appProcessorAuthorization = "app-owned-processor"
let appProcessorAuthorizationEnv = "TSRS_PROCESSOR_AUTH"

func processorIsAppAuthorized(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    environment[appProcessorAuthorizationEnv] == appProcessorAuthorization
}

// Mirrors core/message.ts spokenText: optional line prefix, type prefix for
// non-update relays, then the message body.
func spokenRelayText(line: String, type: String, message: String, includeLine: Bool) -> String {
    let typePrefix = type == "update" ? "" : "\(type). "
    let linePrefix = includeLine ? "\(line). " : ""
    return "\(linePrefix)\(typePrefix)\(message)"
}

struct RelayCliResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

let relayCliUsage = """
Usage: relay <command> [options]

Commands:
  --line <line> --message <message> [--type <type>] [--priority <priority>]
            [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]
                       Validate and enqueue a relay.
  list                 List relays.
  status               Print queue status JSON.
  state                Print focus/ready/mute state.
  ready                Release one relay.
  focus                Keep queued relays quiet.
  mute                 Mute playback.
  unmute               Unmute playback.
  clear                Clear queued and delivered relays.
  clear-line --line <line>
                       Clear queued relays for one line.
  clear-delivered [--line <line>]
                       Clear delivered relays.
  skip-next [--line <line>]
                       Skip the next queued relay.
  acknowledge [--line <line>]
                       Mark the latest delivered relay handled.
  replay-last [--line <line>]
                       Replay the latest delivered relay.
  line [line|--line <line>]
                       Get or set active line.
  combiner [--command <command>]
                       Get or set inactive-line combiner command.
  settings [--combiner-command <command>] [--speech-command <command>]
                       Print settings JSON.
  app-claim-next [--line <line>]
                       Claim the next eligible relay for app-owned playback.
  app-mark-heard --id <id>
                       Mark a relay delivered and record the spoken line.
  app-mark-failed --id <id>
                       Mark a relay failed.
  normalize --line <line> --message <message> [--type <type>] [--priority <priority>]
            [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]
                       Validate and normalize a relay without writing to the queue.
  --version            Print the CLI version.
  help                 Print this help.

This Swift target is the active `relay` CLI implementation. See
docs/cli-parity-inventory.md for the validation inventory.
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
    case "list":
        return withRelayCliStore { store in
            let state = try store.state()
            let relays = try store.list()
            let lines = ["mode=\(state.mode) muted=\(state.muted)"] + relays.map {
                "#\($0.id) [\($0.status)] [\($0.priority)] \($0.line): \($0.message)"
            }
            return RelayCliResult(stdout: lines.joined(separator: "\n"), stderr: "", exitCode: 0)
        }
    case "status":
        return withRelayCliStore { store in
            let status = try store.statusJSON()
            return RelayCliResult(stdout: status, stderr: "", exitCode: 0)
        }
    case "state":
        return withRelayCliStore { store in
            let state = try store.state()
            let muted = state.muted ? ", muted" : ""
            return RelayCliResult(
                stdout: "\(state.mode)\(muted), active-line=\(state.activeLine ?? "none"), inactive-line-combiner=\(state.inactiveLineCombiner)",
                stderr: "",
                exitCode: 0
            )
        }
    case "ready":
        return withRelayCliStore { store in
            let state = try store.setMode("ready")
            return RelayCliResult(stdout: state.muted ? "release queued, but muted is on" : "ready to release one relay", stderr: "", exitCode: 0)
        }
    case "focus":
        return withRelayCliStore { store in
            _ = try store.setMode("focus")
            return RelayCliResult(stdout: "focus mode on", stderr: "", exitCode: 0)
        }
    case "mute":
        return withRelayCliStore { store in
            try store.setMuted(true)
            return RelayCliResult(stdout: "muted", stderr: "", exitCode: 0)
        }
    case "unmute":
        return withRelayCliStore { store in
            try store.setMuted(false)
            return RelayCliResult(stdout: "unmuted", stderr: "", exitCode: 0)
        }
    case "clear":
        return withRelayCliStore { store in
            let count = try store.clear()
            return RelayCliResult(stdout: "cleared \(count) relays", stderr: "", exitCode: 0)
        }
    case "clear-line":
        return runLineRequiredCommand(Array(arguments.dropFirst())) { store, line in
            let count = try store.clearQueued(line: line)
            return RelayCliResult(stdout: "cleared \(count) queued relays from \(line)", stderr: "", exitCode: 0)
        }
    case "clear-delivered", "clear-heard":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            let count = try store.clearHeard(line: line)
            return RelayCliResult(stdout: "cleared \(count) delivered relays", stderr: "", exitCode: 0)
        }
    case "skip-next":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            if let skipped = try store.skipNextQueued(line: line) {
                return RelayCliResult(stdout: "skipped relay #\(skipped.id)", stderr: "", exitCode: 0)
            }
            return RelayCliResult(stdout: "no queued relay to skip", stderr: "", exitCode: 0)
        }
    case "acknowledge", "mark-handled":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            if let handled = try store.markLatestHeardHandled(line: line) {
                return RelayCliResult(stdout: "handled relay #\(handled.id)", stderr: "", exitCode: 0)
            }
            return RelayCliResult(stdout: "no delivered relay to mark handled", stderr: "", exitCode: 0)
        }
    case "replay-last":
        return runOptionalLineCommand(Array(arguments.dropFirst())) { store, line in
            if let replayed = try store.replayLatestHeard(line: line) {
                return RelayCliResult(stdout: "queued relay #\(replayed.id) for replay", stderr: "", exitCode: 0)
            }
            return RelayCliResult(stdout: "no delivered relay to replay", stderr: "", exitCode: 0)
        }
    case "line":
        return runLineCommand(Array(arguments.dropFirst()))
    case "combiner":
        return runCombinerCommand(Array(arguments.dropFirst()))
    case "settings":
        return runSettingsCommand(Array(arguments.dropFirst()))
    case "app-claim-next":
        return runAppClaimNextCommand(Array(arguments.dropFirst()))
    case "app-mark-heard":
        return runAppMarkStatusCommand(Array(arguments.dropFirst()), status: "heard", recordSpoken: true)
    case "app-mark-failed":
        return runAppMarkStatusCommand(Array(arguments.dropFirst()), status: "failed", recordSpoken: false)
    case "cli-status":
        return runCliStatusCommand(Array(arguments.dropFirst()))
    case "install-cli":
        return runInstallCliCommand(Array(arguments.dropFirst()))
    case "normalize":
        return runNormalizeCommand(Array(arguments.dropFirst()))
    default:
        if command.hasPrefix("--") || command == "enqueue" {
            return runEnqueueCommand(command == "enqueue" ? Array(arguments.dropFirst()) : arguments)
        }

        return RelayCliResult(stdout: "", stderr: "unknown command: \(command)\n\(relayCliUsage)", exitCode: 1)
    }
}

private func withRelayCliStore(_ action: (RelayCliStore) throws -> RelayCliResult) -> RelayCliResult {
    do {
        let store = try RelayCliStore(path: relayCliDatabasePath())
        defer {
            store.close()
        }
        return try action(store)
    } catch let error as RelayValidationError {
        return RelayCliResult(stdout: "", stderr: error.errorDescription ?? "invalid relay", exitCode: 1)
    } catch let error as RelayCliStoreError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runEnqueueCommand(_ arguments: [String]) -> RelayCliResult {
    let flags: [String: String]

    do {
        flags = try parseRelayFlags(arguments)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }

    return withRelayCliStore { store in
        let relay = try store.enqueue(NewRelayInput(
            line: flags["line"],
            message: flags["message"] ?? "",
            type: flags["type"],
            priority: flags["priority"],
            session: flags["session"],
            app: flags["app"],
            cwd: flags["cwd"],
            url: flags["url"]
        ))

        return RelayCliResult(stdout: "queued relay #\(relay.id) \(relay.line): \(relay.message)", stderr: "", exitCode: 0)
    }
}

private func runCliStatusCommand(_ arguments: [String]) -> RelayCliResult {
    do {
        let flags = try parseRelayFlags(arguments, knownFlags: relayCliInstallFlags)
        return RelayCliResult(stdout: try cliInstallStatus(sourcePath: flags["source"], targetPath: flags["target"]).json(), stderr: "", exitCode: 0)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch let error as RelayCliStoreError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runInstallCliCommand(_ arguments: [String]) -> RelayCliResult {
    do {
        let flags = try parseRelayFlags(arguments, knownFlags: relayCliInstallFlags)
        let status = try installRelayCli(sourcePath: flags["source"], targetPath: flags["target"])
        return RelayCliResult(stdout: try status.json(), stderr: "", exitCode: 0)
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch let error as RelayCliStoreError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runOptionalLineCommand(_ arguments: [String], action: (RelayCliStore, String?) throws -> RelayCliResult) -> RelayCliResult {
        do {
            let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
            return withRelayCliStore { store in
                try action(store, flags["line"])
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runLineRequiredCommand(_ arguments: [String], action: (RelayCliStore, String) throws -> RelayCliResult) -> RelayCliResult {
        do {
            let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
            guard let line = flags["line"] else {
                return RelayCliResult(stdout: "", stderr: "line is required", exitCode: 1)
            }
            return withRelayCliStore { store in
                try action(store, line)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runLineCommand(_ arguments: [String]) -> RelayCliResult {
        if arguments.isEmpty {
            return withRelayCliStore { store in
                RelayCliResult(stdout: try store.state().activeLine ?? "none", stderr: "", exitCode: 0)
            }
        }

        do {
            let line: String
            if arguments.first == "--line" {
                let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
                guard let requested = flags["line"] else {
                    return RelayCliResult(stdout: "", stderr: "line is required", exitCode: 1)
                }
                line = requested
            } else {
                line = arguments[0]
            }

            return withRelayCliStore { store in
                let state = try store.setActiveLine(line)
                return RelayCliResult(stdout: "active line set to \(state.activeLine ?? line)", stderr: "", exitCode: 0)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runCombinerCommand(_ arguments: [String]) -> RelayCliResult {
        if arguments.isEmpty {
            return withRelayCliStore { store in
                RelayCliResult(stdout: try store.inactiveLineCombinerCommand(), stderr: "", exitCode: 0)
            }
        }

        do {
            let flags = try parseRelayFlags(arguments, knownFlags: ["command", "tool"])
            let requested = flags["command"] ?? flags["tool"] ?? ""
            return withRelayCliStore { store in
                let state = try store.setInactiveLineCombinerCommand(requested == "none" ? "" : requested)
                return RelayCliResult(stdout: "inactive line combiner set to \(state.inactiveLineCombiner)", stderr: "", exitCode: 0)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
        }
}

private func runSettingsCommand(_ arguments: [String]) -> RelayCliResult {
        do {
            let flags = try parseRelayFlags(arguments, knownFlags: ["combiner-command", "speech-command"])
            return withRelayCliStore { store in
                if let command = flags["combiner-command"] {
                    _ = try store.setInactiveLineCombinerCommand(command)
                }
                if let command = flags["speech-command"] {
                    try store.setSpeechCommand(command)
                }
                return RelayCliResult(stdout: try store.settingsJSON(), stderr: "", exitCode: 0)
            }
        } catch let error as RelayCliFlagError {
            return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
        } catch {
            return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runAppClaimNextCommand(_ arguments: [String]) -> RelayCliResult {
    guard processorIsAppAuthorized() else {
        return RelayCliResult(stdout: "", stderr: "app helper commands require TSRS app authorization", exitCode: 1)
    }

    do {
        let flags = try parseRelayFlags(arguments, knownFlags: ["line"])
        return withRelayCliStore { store in
            _ = try store.failStaleSpeaking()
            let activeLine = try store.state().activeLine

            let relay: RelayCliStoredRelay?
            if let line = flags["line"] {
                relay = try store.claimNextForLine(line)
            } else if let activeLine, try store.queuedCountForLine(activeLine) > 0 {
                relay = try store.claimNextForLine(activeLine)
            } else {
                relay = try store.claimNextForSpeech()
            }

            guard let relay else {
                return RelayCliResult(stdout: "null", stderr: "", exitCode: 0)
            }

            let includeLine = try store.shouldPrefixSpokenLine(relay.line)
            let text = spokenRelayText(line: relay.line, type: relay.type, message: relay.message, includeLine: includeLine)
            let json = try jsonString([
                "id": relay.id,
                "text": text,
                "line": relay.line,
            ])
            return RelayCliResult(stdout: json, stderr: "", exitCode: 0)
        }
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
    }
}

private func runAppMarkStatusCommand(_ arguments: [String], status: String, recordSpoken: Bool) -> RelayCliResult {
    guard processorIsAppAuthorized() else {
        return RelayCliResult(stdout: "", stderr: "app helper commands require TSRS app authorization", exitCode: 1)
    }

    do {
        let flags = try parseRelayFlags(arguments, knownFlags: ["id"])
        guard let idText = flags["id"], let id = Int(idText) else {
            return RelayCliResult(stdout: "", stderr: "id is required", exitCode: 1)
        }
        return withRelayCliStore { store in
            let relay = try store.markStatus(id: id, status: status)
            if recordSpoken {
                try store.recordSpokenLine(relay.line)
            }
            return RelayCliResult(stdout: "\(status) #\(relay.id)", stderr: "", exitCode: 0)
        }
    } catch let error as RelayCliFlagError {
        return RelayCliResult(stdout: "", stderr: error.message, exitCode: 1)
    } catch {
        return RelayCliResult(stdout: "", stderr: "\(error)", exitCode: 1)
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
private let relayCliInstallFlags: Set<String> = ["source", "target"]

private func parseRelayFlags(_ arguments: [String]) throws -> [String: String] {
    try parseRelayFlags(arguments, knownFlags: relayCliKnownFlags)
}

private func parseRelayFlags(_ arguments: [String], knownFlags: Set<String>) throws -> [String: String] {
    var flags: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let token = arguments[index]

        guard token.hasPrefix("--") else {
            throw RelayCliFlagError(message: "unexpected argument: \(token)")
        }

        let name = String(token.dropFirst(2))

        guard knownFlags.contains(name) else {
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

// MARK: - SQLite queue store

struct RelayCliStoredRelay {
    let id: Int
    let line: String
    let message: String
    let type: String
    let priority: String
    let status: String
}

struct RelayCliQueueState {
    let mode: String
    let muted: Bool
    let inactiveLineCombiner: String
    let activeLine: String?
}

private struct RelayCliStoreError: Error {
    let message: String
}

private final class RelayCliStore {
    private let database: OpaquePointer

    init(path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            throw RelayCliStoreError(message: "could not open relay database")
        }

        database = opened
        sqlite3_busy_timeout(database, 2_000)
        try migrate()
    }

    func close() {
        sqlite3_close(database)
    }

    func enqueue(_ input: NewRelayInput) throws -> RelayCliStoredRelay {
        let relay = try normalizeRelay(input)
        let state = try state()

        if let activeLine = state.activeLine, relay.line != activeLine {
            // Inactive-line direct behavior keeps only the latest relay for the
            // line. The shipped `relay` binary never runs the external combiner,
            // so native parity is latest-only collapse.
            _ = try clearQueued(line: relay.line)
            return try insertRelay(relay)
        }

        let inserted = try insertRelay(relay)
        try setSettingIfMissing(key: "active_line", value: inserted.line)
        return inserted
    }

    private func insertRelay(_ relay: NormalizedRelay) throws -> RelayCliStoredRelay {
        let now = nowString()
        return try returningRelay("""
            INSERT INTO relays (
              line, message, type, priority, session, app, cwd, url, status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
            RETURNING id, line, message, type, priority, status
        """, [
            relay.line,
            relay.message,
            relay.type,
            relay.priority,
            relay.session,
            relay.app,
            relay.cwd,
            relay.url,
            now,
            now,
        ])
    }

    func queuedCountForLine(_ line: String) throws -> Int {
        var count = 0
        try query("""
            SELECT COUNT(*) AS count
            FROM relays
            WHERE status = 'queued' AND line = ?
        """, [line]) { statement in
            count = Int(sqlite3_column_int(statement, 0))
        }
        return count
    }

    func list(limit: Int = 20) throws -> [RelayCliStoredRelay] {
        var relays: [RelayCliStoredRelay] = []
        try query("""
            SELECT id, line, message, type, priority, status
            FROM relays
            ORDER BY
              CASE status
                WHEN 'speaking' THEN 0
                WHEN 'queued' THEN 1
                WHEN 'heard' THEN 2
                ELSE 3
              END,
              created_at ASC
            LIMIT ?
        """, [String(limit)]) { statement in
            relays.append(mapRelay(statement))
        }
        return relays
    }

    func state() throws -> RelayCliQueueState {
        let settings = try rawSettings()
        return RelayCliQueueState(
            mode: settings["mode"] == "ready" ? "ready" : "focus",
            muted: settings["muted"] == "true",
            inactiveLineCombiner: commandIsEnabled(settings["inactive_line_combiner_command"]) ? "custom" : "none",
            activeLine: settings["active_line"]
        )
    }

    func statusJSON() throws -> String {
        _ = try expireStaleRelays()
        let state = try state()
        let counts = try countsByStatus()
        let lines = try lineSummaries()
        var object: [String: Any] = [
            "profile": "direct",
            "mode": state.mode,
            "muted": state.muted,
            "inactiveLineCombiner": state.inactiveLineCombiner,
            "inactiveLineCombinerCommand": try inactiveLineCombinerCommand(),
            "speechCommand": try speechCommand(),
            "activeLine": state.activeLine as Any,
            "counts": counts,
            "queueCount": counts["queued"] ?? 0,
            "attentionCount": (counts["queued"] ?? 0) + (counts["heard"] ?? 0) + (counts["failed"] ?? 0),
            "overview": try queueOverview(),
            "lines": lines,
            "capabilities": directRelayCapabilities,
        ]

        let lineSources = try latestSourceContextsByLine()
        if !lineSources.isEmpty {
            var sources: [String: Any] = [:]
            for source in lineSources {
                if let line = source["line"] as? String {
                    sources[line] = source
                }
            }
            object["lineSources"] = sources
        }

        return try jsonString(object)
    }

    func settingsJSON() throws -> String {
        let state = try state()
        let object: [String: Any] = [
            "profile": "direct",
            "inactiveLineCombiner": state.inactiveLineCombiner,
            "inactiveLineCombinerCommand": try inactiveLineCombinerCommand(),
            "speechCommand": try speechCommand(),
            "capabilities": directRelayCapabilities,
        ]
        return try jsonString(object)
    }

    func setMode(_ mode: String) throws -> RelayCliQueueState {
        try setSetting(key: "mode", value: mode)
        return try state()
    }

    func setMuted(_ muted: Bool) throws {
        try setSetting(key: "muted", value: String(muted))
    }

    func setActiveLine(_ line: String) throws -> RelayCliQueueState {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            throw RelayCliStoreError(message: "line is required")
        }
        try setSetting(key: "active_line", value: normalized)
        return try state()
    }

    func inactiveLineCombinerCommand() throws -> String {
        try rawSettings()["inactive_line_combiner_command"] ?? defaultInactiveLineCombinerCommand
    }

    func setInactiveLineCombinerCommand(_ command: String) throws -> RelayCliQueueState {
        try setSetting(key: "inactive_line_combiner_command", value: resetBlankCommand(command, fallback: defaultInactiveLineCombinerCommand))
        return try state()
    }

    func speechCommand() throws -> String {
        try rawSettings()["speech_command"] ?? defaultSpeechCommand
    }

    func setSpeechCommand(_ command: String) throws {
        try setSetting(key: "speech_command", value: resetBlankCommand(command, fallback: defaultSpeechCommand))
    }

    func clear() throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status IN ('queued', 'heard', 'handled', 'skipped', 'expired', 'failed')
        """)
    }

    func clearQueued(line: String) throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status = 'queued' AND line = ?
        """, [line])
    }

    func clearHeard(line: String?) throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status = 'heard' AND (? IS NULL OR line = ?)
        """, [line, line])
    }

    func skipNextQueued(line: String?) throws -> RelayCliStoredRelay? {
        try markFirstMatchingStatus(from: "queued", to: "skipped", line: line)
    }

    func markLatestHeardHandled(line: String?) throws -> RelayCliStoredRelay? {
        try markLatestMatchingStatus(from: "heard", to: "handled", line: line)
    }

    func replayLatestHeard(line: String?) throws -> RelayCliStoredRelay? {
        try markLatestMatchingStatus(from: "heard", to: "queued", line: line)
    }

    func expireStaleRelays(ageMinutes: Int = 30) throws -> Int {
        let now = Date()
        let staleBefore = nowString(from: now.addingTimeInterval(TimeInterval(-ageMinutes * 60)))
        return try changes("""
            UPDATE relays
            SET status = 'expired', updated_at = ?
            WHERE (
              status IN ('heard', 'failed') AND updated_at <= ?
            ) OR (
              status = 'queued'
              AND priority != 'high'
              AND type IN ('update', 'complete')
              AND created_at <= ?
            )
        """, [nowString(from: now), staleBefore, staleBefore])
    }

    func failStaleSpeaking(ttlSeconds: Int = 60) throws -> Int {
        let now = Date()
        let staleBefore = nowString(from: now.addingTimeInterval(TimeInterval(-ttlSeconds)))
        return try changes("""
            UPDATE relays
            SET status = 'failed', updated_at = ?
            WHERE status = 'speaking' AND updated_at <= ?
        """, [nowString(from: now), staleBefore])
    }

    func claimNextForSpeech() throws -> RelayCliStoredRelay? {
        let state = try state()
        if state.muted || state.mode != "ready" {
            return nil
        }

        let claimed = try optionalReturningRelay("""
            UPDATE relays
            SET status = 'speaking', updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = 'queued'
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [nowString()])

        if claimed == nil {
            return nil
        }

        _ = try setMode("focus")
        return claimed
    }

    func claimNextForLine(_ line: String) throws -> RelayCliStoredRelay? {
        if try state().muted {
            return nil
        }

        return try optionalReturningRelay("""
            UPDATE relays
            SET status = 'speaking', updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = 'queued' AND line = ?
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [nowString(), line])
    }

    func markStatus(id: Int, status: String) throws -> RelayCliStoredRelay {
        guard let relay = try optionalReturningRelay("""
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = ?
            RETURNING id, line, message, type, priority, status
        """, [status, nowString(), String(id)]) else {
            throw RelayCliStoreError(message: "relay \(id) not found")
        }
        return relay
    }

    func recordSpokenLine(_ line: String) throws {
        let payload = try jsonString(["line": line, "spokenAt": nowString()])
        try setSetting(key: "last_spoken_line", value: payload)
    }

    func shouldPrefixSpokenLine(_ line: String, timeoutSeconds: Double = 60) throws -> Bool {
        guard let last = try lastSpokenLine(), last.line == line else {
            return true
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let spokenAt = formatter.date(from: last.spokenAt) else {
            return true
        }

        return Date().timeIntervalSince(spokenAt) >= timeoutSeconds
    }

    private func lastSpokenLine() throws -> (line: String, spokenAt: String)? {
        guard
            let value = try rawSettings()["last_spoken_line"],
            let data = value.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let line = parsed["line"] as? String,
            let spokenAt = parsed["spokenAt"] as? String
        else {
            return nil
        }
        return (line, spokenAt)
    }

    func queueOverview(staleBlockerAgeMinutes: Int = 15, limit: Int = 10) throws -> [String: Any] {
        let now = Date()
        let staleBefore = nowString(from: now.addingTimeInterval(TimeInterval(-staleBlockerAgeMinutes * 60)))

        var priorityCounts: [String: Int] = [:]
        try query("""
            SELECT priority, COUNT(*) AS count
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY priority
        """) { statement in
            if let priority = columnString(statement, 0) {
                priorityCounts[priority] = Int(sqlite3_column_int(statement, 1))
            }
        }

        var byPriority: [[String: Any]] = []
        for priority in relayPriorities.reversed() {
            if let count = priorityCounts[priority], count > 0 {
                byPriority.append(["priority": priority, "count": count])
            }
        }

        var byProducer: [[String: Any]] = []
        try query("""
            SELECT
              COALESCE(session, app, 'unknown') AS producer,
              COUNT(*) AS count
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY producer
            ORDER BY count DESC, producer ASC
            LIMIT ?
        """, [String(limit)]) { statement in
            if let producer = columnString(statement, 0) {
                byProducer.append(["producer": producer, "count": Int(sqlite3_column_int(statement, 1))])
            }
        }

        var staleCount = 0
        var oldestCreatedAt: String?
        try query("""
            SELECT COUNT(*) AS count, MIN(created_at) AS oldestCreatedAt
            FROM relays
            WHERE status IN ('queued', 'heard')
              AND priority = 'high'
              AND type IN ('blocked', 'needs-input')
              AND created_at <= ?
        """, [staleBefore]) { statement in
            staleCount = Int(sqlite3_column_int(statement, 0))
            oldestCreatedAt = columnString(statement, 1)
        }

        var staleBlockers: [String: Any] = [
            "count": staleCount,
            "thresholdMinutes": staleBlockerAgeMinutes,
        ]
        if staleCount > 0, let oldestCreatedAt {
            staleBlockers["oldestCreatedAt"] = oldestCreatedAt
        }

        return [
            "byPriority": byPriority,
            "byProducer": byProducer,
            "staleBlockers": staleBlockers,
        ]
    }

    func latestSourceContextsByLine() throws -> [[String: Any]] {
        var sources: [[String: Any]] = []
        try query("""
            SELECT id, line, session, app, cwd, url
            FROM relays AS source
            WHERE (cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL)
              AND id = (
                SELECT id
                FROM relays AS candidate
                WHERE candidate.line = source.line
                  AND (
                    candidate.cwd IS NOT NULL
                    OR candidate.url IS NOT NULL
                    OR candidate.app IS NOT NULL
                    OR candidate.session IS NOT NULL
                  )
                ORDER BY created_at DESC, id DESC
                LIMIT 1
            )
            ORDER BY line ASC
        """) { statement in
            var object: [String: Any] = [
                "id": Int(sqlite3_column_int(statement, 0)),
                "line": columnString(statement, 1) ?? "",
            ]
            if let session = columnString(statement, 2) { object["session"] = session }
            if let app = columnString(statement, 3) { object["app"] = app }
            if let cwd = columnString(statement, 4) { object["cwd"] = cwd }
            if let url = columnString(statement, 5) { object["url"] = url }
            sources.append(object)
        }
        return sources
    }

    private func migrate() throws {
        try executeBatch("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS relays (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              line TEXT NOT NULL,
              message TEXT NOT NULL,
              type TEXT NOT NULL,
              priority TEXT NOT NULL,
              session TEXT,
              app TEXT,
              cwd TEXT,
              url TEXT,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
        """)

        try execute("INSERT OR IGNORE INTO schema_migrations (version) VALUES (1)")
        try setSettingIfMissing(key: "mode", value: "focus")
        try setSettingIfMissing(key: "muted", value: "false")
        try setSettingIfMissing(key: "inactive_line_combiner", value: "none")
        try setSettingIfMissing(key: "inactive_line_combiner_command", value: defaultInactiveLineCombinerCommand)
        try setSettingIfMissing(key: "speech_command", value: defaultSpeechCommand)
    }

    private func rawSettings() throws -> [String: String] {
        var settings: [String: String] = [:]
        try query("SELECT key, value FROM settings") { statement in
            if let key = columnString(statement, 0), let value = columnString(statement, 1) {
                settings[key] = value
            }
        }
        return settings
    }

    private func countsByStatus() throws -> [String: Int] {
        var counts = [
            "queued": 0,
            "speaking": 0,
            "heard": 0,
            "handled": 0,
            "skipped": 0,
            "expired": 0,
            "failed": 0,
        ]
        try query("""
            SELECT status, COUNT(*) AS count
            FROM relays
            GROUP BY status
        """) { statement in
            if let status = columnString(statement, 0) {
                counts[status] = Int(sqlite3_column_int(statement, 1))
            }
        }
        return counts
    }

    private func lineSummaries() throws -> [[String: Any]] {
        var lines: [[String: Any]] = []
        try query("""
            SELECT
              line,
              SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued,
              SUM(CASE WHEN status = 'heard' THEN 1 ELSE 0 END) AS heard,
              SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
            FROM relays
            WHERE status IN ('queued', 'heard', 'failed')
            GROUP BY line
            HAVING queued > 0 OR heard > 0 OR failed > 0
            ORDER BY queued DESC, heard DESC, failed DESC, line ASC
        """) { statement in
            if let line = columnString(statement, 0) {
                lines.append([
                    "line": line,
                    "queued": Int(sqlite3_column_int(statement, 1)),
                    "heard": Int(sqlite3_column_int(statement, 2)),
                    "failed": Int(sqlite3_column_int(statement, 3)),
                ])
            }
        }
        return lines
    }

    private func setSetting(key: String, value: String) throws {
        try execute("""
            INSERT INTO settings (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, [key, value])
    }

    private func setSettingIfMissing(key: String, value: String) throws {
        try execute("""
            INSERT OR IGNORE INTO settings (key, value)
            VALUES (?, ?)
        """, [key, value])
    }

    private func returningRelay(_ sql: String, _ values: [String?]) throws -> RelayCliStoredRelay {
        var relay: RelayCliStoredRelay?
        try query(sql, values) { statement in
            relay = mapRelay(statement)
        }

        guard let relay else {
            throw RelayCliStoreError(message: "relay insert failed")
        }

        return relay
    }

    private func optionalReturningRelay(_ sql: String, _ values: [String?]) throws -> RelayCliStoredRelay? {
        var relay: RelayCliStoredRelay?
        try query(sql, values) { statement in
            relay = mapRelay(statement)
        }
        return relay
    }

    private func markFirstMatchingStatus(from: String, to: String, line: String?) throws -> RelayCliStoredRelay? {
        try optionalReturningRelay("""
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = ? AND (? IS NULL OR line = ?)
              ORDER BY
                CASE priority
                  WHEN 'high' THEN 0
                  WHEN 'normal' THEN 1
                  ELSE 2
                END,
                created_at ASC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [to, nowString(), from, line, line])
    }

    private func markLatestMatchingStatus(from: String, to: String, line: String?) throws -> RelayCliStoredRelay? {
        try optionalReturningRelay("""
            UPDATE relays
            SET status = ?, updated_at = ?
            WHERE id = (
              SELECT id
              FROM relays
              WHERE status = ? AND (? IS NULL OR line = ?)
              ORDER BY updated_at DESC, id DESC
              LIMIT 1
            )
            RETURNING id, line, message, type, priority, status
        """, [to, nowString(), from, line, line])
    }

    private func changes(_ sql: String, _ values: [String?] = []) throws -> Int {
        try execute(sql, values)
        return Int(sqlite3_changes(database))
    }

    private func execute(_ sql: String, _ values: [String?] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RelayCliStoreError(message: sqliteError(database))
        }
        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)

        if sqlite3_step(statement) != SQLITE_DONE {
            throw RelayCliStoreError(message: sqliteError(database))
        }
    }

    private func executeBatch(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)

        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? sqliteError(database)
            sqlite3_free(error)
            throw RelayCliStoreError(message: message)
        }
    }

    private func query(_ sql: String, _ values: [String?] = [], row: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RelayCliStoreError(message: sqliteError(database))
        }
        defer {
            sqlite3_finalize(statement)
        }

        bind(values, to: statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }
}

func relayCliDatabasePath() -> String {
    let environment = ProcessInfo.processInfo.environment

    if let path = environment["TSRS_DB_PATH"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return path
    }

    let home = environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Application Support/Tri-State Relay Service/relay.db"
}

private struct NativeRelayCliInstallStatus {
    let status: String
    let sourcePath: String
    let targetPath: String
    let sourceSignature: String?
    let targetSignature: String?
    let targetDirectoryOnPath: Bool
    let version: String
    let message: String

    func json() throws -> String {
        var object: [String: Any] = [
            "status": status,
            "sourcePath": sourcePath,
            "targetPath": targetPath,
            "targetDirectoryOnPath": targetDirectoryOnPath,
            "version": version,
            "message": message,
        ]
        if let sourceSignature {
            object["sourceSignature"] = sourceSignature
        }
        if let targetSignature {
            object["targetSignature"] = targetSignature
        }
        return try jsonString(object)
    }
}

private func cliInstallStatus(sourcePath: String?, targetPath: String?) throws -> NativeRelayCliInstallStatus {
    let sourcePath = sourcePath ?? currentRelayExecutable()
    let targetPath = targetPath ?? ProcessInfo.processInfo.environment["TSRS_RELAY_INSTALL_TARGET"] ?? defaultCliInstallTarget()
    let targetDirectoryOnPath = pathContainsDirectory(URL(fileURLWithPath: targetPath).deletingLastPathComponent().path)

    guard FileManager.default.fileExists(atPath: sourcePath) else {
        return NativeRelayCliInstallStatus(status: "source-missing", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: nil, targetSignature: nil, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay source is missing: \(sourcePath)")
    }

    let sourceSignature = try fileSignature(sourcePath)

    guard FileManager.default.fileExists(atPath: targetPath) else {
        return NativeRelayCliInstallStatus(status: "missing", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: nil, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay CLI is not installed at \(targetPath)")
    }

    let targetSignature = try fileSignature(targetPath)

    if filesAreEqual(sourcePath, targetPath) {
        return NativeRelayCliInstallStatus(status: "current", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: targetSignature, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay CLI is current at \(targetPath)")
    }

    if !targetLooksLikeRelay(targetPath) {
        return NativeRelayCliInstallStatus(status: "foreign", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: targetSignature, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "\(targetPath) exists but does not look like a TSRS relay CLI")
    }

    return NativeRelayCliInstallStatus(status: "stale", sourcePath: sourcePath, targetPath: targetPath, sourceSignature: sourceSignature, targetSignature: targetSignature, targetDirectoryOnPath: targetDirectoryOnPath, version: relayCliVersion, message: "relay CLI at \(targetPath) differs from bundled version \(relayCliVersion)")
}

private func installRelayCli(sourcePath: String?, targetPath: String?) throws -> NativeRelayCliInstallStatus {
    let status = try cliInstallStatus(sourcePath: sourcePath, targetPath: targetPath)

    if status.status == "current" {
        return status
    }

    if status.status == "source-missing" || status.status == "foreign" {
        throw RelayCliStoreError(message: status.message)
    }

    let targetDirectory = URL(fileURLWithPath: status.targetPath).deletingLastPathComponent().path
    try FileManager.default.createDirectory(atPath: targetDirectory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: status.targetPath) {
        try FileManager.default.removeItem(atPath: status.targetPath)
    }
    try FileManager.default.copyItem(atPath: status.sourcePath, toPath: status.targetPath)
    let permissions = (try FileManager.default.attributesOfItem(atPath: status.sourcePath)[.posixPermissions] as? NSNumber)?.intValue ?? 0o755
    try FileManager.default.setAttributes([.posixPermissions: permissions | 0o755], ofItemAtPath: status.targetPath)
    return try cliInstallStatus(sourcePath: sourcePath, targetPath: targetPath)
}

private func defaultCliInstallTarget() -> String {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/.local/bin/relay"
}

private func currentRelayExecutable() -> String {
    if let source = ProcessInfo.processInfo.environment["TSRS_RELAY_SOURCE"] {
        return source
    }

    return CommandLine.arguments.first ?? ProcessInfo.processInfo.arguments.first ?? ""
}

private func fileSignature(_ path: String) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(size):\(modified * 1000)"
}

private func filesAreEqual(_ left: String, _ right: String) -> Bool {
    guard
        let leftData = FileManager.default.contents(atPath: left),
        let rightData = FileManager.default.contents(atPath: right)
    else {
        return false
    }

    return leftData == rightData
}

private func targetLooksLikeRelay(_ path: String) -> Bool {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return false
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    return process.terminationStatus == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("relay ")
}

private func pathContainsDirectory(_ directory: String) -> Bool {
    (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .contains { String($0) == directory }
}

private func mapRelay(_ statement: OpaquePointer) -> RelayCliStoredRelay {
    RelayCliStoredRelay(
        id: Int(sqlite3_column_int(statement, 0)),
        line: columnString(statement, 1) ?? "",
        message: columnString(statement, 2) ?? "",
        type: columnString(statement, 3) ?? "update",
        priority: columnString(statement, 4) ?? "normal",
        status: columnString(statement, 5) ?? "queued"
    )
}

private func bind(_ values: [String?], to statement: OpaquePointer) {
    for (index, value) in values.enumerated() {
        let position = Int32(index + 1)

        if let value {
            sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, position)
        }
    }
}

func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else {
        return nil
    }

    return String(cString: text)
}

func sqliteError(_ database: OpaquePointer) -> String {
    if let message = sqlite3_errmsg(database) {
        return String(cString: message)
    }

    return "unknown sqlite error"
}

private func nowString(from date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func jsonString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

func commandIsEnabled(_ command: String?) -> Bool {
    guard let command else {
        return false
    }

    for line in command.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
            return true
        }
    }

    return false
}

func resetBlankCommand(_ command: String, fallback: String) -> String {
    commandIsEnabled(command) ? command : fallback
}

let defaultInactiveLineCombinerCommand = """
# Inactive line combiner command.
# Leave this commented to use latest-only inactive-line behavior.
# The command must print a JSON object: {"action":"replace|promote|drop","type":"update|blocked|complete","priority":"low|normal|high","message":"short relay"}
# Placeholders are inserted as single argv values, not shell-expanded.
#
# llm CLI: https://github.com/simonw/llm
# llm prompt <input> --system <system> --no-stream --no-log
#
# apfel CLI: https://github.com/Arthur-Ficial/apfel
# apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>
"""

let defaultSpeechCommand = """
# Speech command.
# /usr/bin/say ships with macOS, so no extra install is required.
# Placeholders are inserted as single argv values, not shell-expanded.
/usr/bin/say <message>
"""

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
