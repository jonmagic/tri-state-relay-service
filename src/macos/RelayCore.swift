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
  state                Print focus/ready/mute state.
  ready                Release one relay.
  focus                Keep queued relays quiet.
  mute                 Mute playback.
  unmute               Unmute playback.
  clear                Clear queued and delivered relays.
  normalize --line <line> --message <message> [--type <type>] [--priority <priority>]
            [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]
                       Validate and normalize a relay without writing to the queue.
  --version            Print the CLI version.
  help                 Print this help.

This native target is an in-progress Swift replacement for the Perry-built
`relay` CLI. See docs/cli-parity-inventory.md for the remaining parity gaps.
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
        let now = nowString()
        let inserted = try returningRelay("""
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

        try execute("""
            INSERT OR IGNORE INTO settings (key, value)
            VALUES ('active_line', ?)
        """, [relay.line])

        return inserted
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

    func setMode(_ mode: String) throws -> RelayCliQueueState {
        try setSetting(key: "mode", value: mode)
        return try state()
    }

    func setMuted(_ muted: Bool) throws {
        try setSetting(key: "muted", value: String(muted))
    }

    func clear() throws -> Int {
        try changes("""
            DELETE FROM relays
            WHERE status IN ('queued', 'heard', 'handled', 'skipped', 'expired', 'failed')
        """)
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

private func relayCliDatabasePath() -> String {
    let environment = ProcessInfo.processInfo.environment

    if let path = environment["TSRS_DB_PATH"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return path
    }

    let home = environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Application Support/Tri-State Relay Service/relay.db"
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

private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else {
        return nil
    }

    return String(cString: text)
}

private func sqliteError(_ database: OpaquePointer) -> String {
    if let message = sqlite3_errmsg(database) {
        return String(cString: message)
    }

    return "unknown sqlite error"
}

private func nowString() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func commandIsEnabled(_ command: String?) -> Bool {
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

private let defaultInactiveLineCombinerCommand = """
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

private let defaultSpeechCommand = """
# Speech command.
# /usr/bin/say ships with macOS, so no extra install is required.
# Placeholders are inserted as single argv values, not shell-expanded.
/usr/bin/say <message>
"""

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
