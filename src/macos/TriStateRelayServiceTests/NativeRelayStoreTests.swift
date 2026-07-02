import XCTest
import SQLite3
@testable import Tri_State_Relay_Service

final class NativeRelayStoreTests: XCTestCase {
    func testFreshDatabaseDefaultSettings() throws {
        let missingDirectory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databasePath = missingDirectory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: missingDirectory)
        }
        
        let store = NativeRelayStore(profile: "direct")
        
        let settings = store.loadSettings()
        XCTAssertTrue(settings.inactiveLineCombinerCommand.contains("Inactive line combiner command."))
        XCTAssertTrue(settings.voiceCommand.contains("Voice command."))
        XCTAssertEqual(settings.cleanupRetentionMinutes, defaultCleanupRetentionMinutes)
        XCTAssertEqual(settings.commandPaletteShortcut.identifier, "control-option-command-space")
        XCTAssertFalse(settings.firstStartSetupComplete)
        
        let status = store.loadStatus()
        XCTAssertEqual(status.mode, "focus")
        XCTAssertEqual(status.muted, false)
        XCTAssertEqual(status.queued, 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: databasePath))
        let database = try DatabaseSnapshot(path: databasePath)
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'mode'"), "focus")
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'muted'"), "false")
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'command_palette_shortcut'"), "control-option-command-space")
        XCTAssertTrue(database.scalar("SELECT value FROM settings WHERE key = 'voice_command'")?.contains("Voice command.") == true)
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'cleanup_retention_minutes'"), String(defaultCleanupRetentionMinutes))
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'first_start_setup_complete'"), "false")
        XCTAssertEqual(database.scalar("SELECT version FROM schema_migrations WHERE version = 1"), "1")
        XCTAssertEqual(database.scalar("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'relays_status_idx'"), "relays_status_idx")
        XCTAssertEqual(database.scalar("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'relays_status_line_idx'"), "relays_status_line_idx")
        XCTAssertEqual(database.scalar("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'relays_source_context_latest_idx'"), "relays_source_context_latest_idx")
        XCTAssertEqual(database.scalar("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'spoken_usage_daily'"), "spoken_usage_daily")
        XCTAssertEqual(database.scalar("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'spoken_usage_daily_day_idx'"), "spoken_usage_daily_day_idx")
        XCTAssertEqual(database.scalar("PRAGMA journal_mode"), "wal")
    }

    func testCommandPaletteShortcutPersists() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        store.saveCommandPaletteShortcut(KeyboardShortcut(identifier: "control-shift-command-y"))

        XCTAssertEqual(NativeRelayStore(profile: "direct").loadSettings().commandPaletteShortcut.identifier, "control-shift-command-y")
    }

    func testStartupCleanupPrunesOldTerminalRowsAndUsageBuckets() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        store.saveCleanupRetentionMinutes(1)

        let database = try DatabaseSnapshot(path: databasePath)
        database.execute("INSERT INTO relays (line, message, type, priority, status, created_at, updated_at) VALUES ('Brain', 'old expired', 'update', 'normal', 'expired', '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z')")
        database.execute("INSERT INTO relays (line, message, type, priority, status, created_at, updated_at) VALUES ('Brain', 'still queued', 'update', 'normal', 'queued', '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z')")
        database.execute("INSERT INTO spoken_usage_daily (day, provider, model, voice_identifier, line, relay_count, character_count, updated_at) VALUES ('2000-01-01', 'apple', 'direct-say', 'default', 'Brain', 1, 10, '2000-01-01T00:00:00.000Z')")

        store.cleanupOnStartup()

        XCTAssertEqual(database.scalar("SELECT COUNT(*) FROM relays WHERE status = 'expired'"), "0")
        XCTAssertEqual(database.scalar("SELECT COUNT(*) FROM relays WHERE status = 'queued'"), "1")
        XCTAssertEqual(database.scalar("SELECT COUNT(*) FROM spoken_usage_daily"), "0")
    }

    func testFirstStartSetupCompletionPersistsAndDoesNotRetrigger() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        XCTAssertTrue(store.needsFirstStartSetup())

        store.completeFirstStartSetup()

        XCTAssertFalse(store.needsFirstStartSetup())
        XCTAssertFalse(NativeRelayStore(profile: "direct").needsFirstStartSetup())
        let database = try DatabaseSnapshot(path: databasePath)
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'first_start_setup_complete'"), "true")
    }

    func testExistingDatabaseDefaultsFirstStartSetupToComplete() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path

        let database = try DatabaseSnapshot(path: databasePath)
        database.execute("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        database.execute("CREATE TABLE relays (id INTEGER PRIMARY KEY AUTOINCREMENT, line TEXT NOT NULL, message TEXT NOT NULL, type TEXT NOT NULL, priority TEXT NOT NULL, session TEXT, app TEXT, cwd TEXT, url TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)")
        database.execute("INSERT INTO settings (key, value) VALUES ('active_line', 'Brain')")

        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertFalse(NativeRelayStore(profile: "direct").needsFirstStartSetup())
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'first_start_setup_complete'"), "true")
    }

    func testLegacyCombinerSettingMigratesOnFreshOpen() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path

        let database = try DatabaseSnapshot(path: databasePath)
        database.execute("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        database.execute("CREATE TABLE relays (id INTEGER PRIMARY KEY AUTOINCREMENT, line TEXT NOT NULL, message TEXT NOT NULL, type TEXT NOT NULL, priority TEXT NOT NULL, session TEXT, app TEXT, cwd TEXT, url TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)")
        database.execute("INSERT INTO settings (key, value) VALUES ('inactive_line_combiner', 'llm')")

        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let settings = NativeRelayStore(profile: "direct").loadSettings()
        XCTAssertEqual(settings.inactiveLineCombinerCommand, "llm prompt <input> --system <system> --no-stream --no-log")
    }

    func testRecentLineMessagesReturnQueuedThenDelivered() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        let deliveredOlder = try XCTUnwrap(try store.enqueue(NewRelayInput(line: "Brain", message: "delivered older", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil)))
        let deliveredNewer = try XCTUnwrap(try store.enqueue(NewRelayInput(line: "Brain", message: "delivered newer", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil)))
        _ = store.claimQueuedMessageForNativeSpeech(line: "Brain", id: deliveredOlder.id)
        store.markNativeSpeechHeard(id: deliveredOlder.id)
        _ = store.claimQueuedMessageForNativeSpeech(line: "Brain", id: deliveredNewer.id)
        store.markNativeSpeechHeard(id: deliveredNewer.id)
        _ = try store.enqueue(NewRelayInput(line: "Brain", message: "queued low", type: "update", priority: "low", session: nil, app: nil, cwd: nil, url: nil))
        _ = try store.enqueue(NewRelayInput(line: "Brain", message: "queued high", type: "update", priority: "high", session: nil, app: nil, cwd: nil, url: nil))
        _ = try store.enqueue(NewRelayInput(line: "Other", message: "other line", type: "update", priority: "high", session: nil, app: nil, cwd: nil, url: nil))

        let messages = store.recentMessages(line: "Brain")

        XCTAssertEqual(messages.map(\.message), ["queued high", "queued low", "delivered newer", "delivered older"])
        XCTAssertEqual(messages.map(\.displayStatus), ["Queued", "Queued", "Delivered", "Delivered"])
    }

    func testMarkNativeSpeechHeardRecordsAggregateSpokenUsage() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        let first = try XCTUnwrap(try store.enqueue(NewRelayInput(line: "Brain", message: "first", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil)))
        let second = try XCTUnwrap(try store.enqueue(NewRelayInput(line: "Brain", message: "second", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil)))

        XCTAssertEqual(store.claimQueuedMessageForNativeSpeech(line: "Brain", id: first.id)?.text, "Brain. first")
        store.markNativeSpeechHeard(id: first.id)
        XCTAssertEqual(store.claimQueuedMessageForNativeSpeech(line: "Brain", id: second.id)?.text, "second")
        store.markNativeSpeechHeard(id: second.id)

        let database = try DatabaseSnapshot(path: databasePath)
        XCTAssertEqual(database.scalar("SELECT relay_count FROM spoken_usage_daily WHERE line = 'Brain' AND provider = 'apple' AND model = 'direct-say'"), "2")
        XCTAssertEqual(database.scalar("SELECT character_count FROM spoken_usage_daily WHERE line = 'Brain' AND provider = 'apple' AND model = 'direct-say'"), "18")
    }

    func testLoadStatusUsesLatestSourceContextByLine() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        _ = try store.enqueue(NewRelayInput(line: "Brain", message: "older", type: "update", priority: "normal", session: "session-1", app: "App One", cwd: nil, url: nil))
        _ = try store.enqueue(NewRelayInput(line: "Brain", message: "newer", type: "update", priority: "normal", session: "session-2", app: "App Two", cwd: "/tmp/newer", url: nil))

        let source = try XCTUnwrap(store.loadStatus().lineSources["Brain"])
        XCTAssertEqual(source.path, "/tmp/newer")
    }

    func testClaimQueuedMessageForNativeSpeechMarksExactQueuedMessage() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = NativeRelayStore(profile: "direct")
        let first = try XCTUnwrap(try store.enqueue(NewRelayInput(line: "Brain", message: "first queued", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil)))
        let second = try XCTUnwrap(try store.enqueue(NewRelayInput(line: "Brain", message: "second queued", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil)))

        let claim = store.claimQueuedMessageForNativeSpeech(line: "Brain", id: second.id)

        XCTAssertEqual(claim?.id, second.id)
        XCTAssertEqual(store.recentMessages(line: "Brain").map(\.id), [first.id])
        store.markNativeSpeechHeard(id: second.id)
        XCTAssertEqual(store.recentMessages(line: "Brain").map(\.message), ["first queued", "second queued"])
    }

    func testConfiguredInactiveLineCombinerReplacesPendingDigest() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let script = try inactiveCombinerScript(outputMessage: "Other summary: setup issue is isolated to the old CLI path.")
        let store = NativeRelayStore(profile: "direct")
        store.saveSettings(inactiveLineCombinerCommand: "\(script) <input> <system>", voiceIdentifier: defaultSpeechVoiceIdentifier, commandPaletteShortcut: .defaultCommandPalette)
        _ = try store.enqueue(NewRelayInput(line: "Brain", message: "active", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil))
        store.setActiveLine("Brain")

        _ = try store.enqueue(NewRelayInput(line: "Other", message: "first inactive", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil))
        _ = try store.enqueue(NewRelayInput(line: "Other", message: "second inactive", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil))

        XCTAssertEqual(store.recentMessages(line: "Other").map(\.message), ["Other summary: setup issue is isolated to the old CLI path."])
    }

    func testActiveLineChangeWhileCombiningDoesNotClearNewActiveLine() throws {
        let directory = testArtifactDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databasePath = directory.appendingPathComponent("relay.db").path
        setenv("TSRS_DB_PATH", databasePath, 1)
        defer {
            unsetenv("TSRS_DB_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let startedPath = directory.appendingPathComponent("started").path
        let releasePath = directory.appendingPathComponent("release").path
        let script = try blockingInactiveCombinerScript(outputMessage: "Other summary should not be inserted after line switch.", startedPath: startedPath, releasePath: releasePath)
        let store = NativeRelayStore(profile: "direct")
        store.saveSettings(inactiveLineCombinerCommand: "\(script) <input> <system>", voiceIdentifier: defaultSpeechVoiceIdentifier, commandPaletteShortcut: .defaultCommandPalette)
        _ = try store.enqueue(NewRelayInput(line: "Brain", message: "active", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil))
        store.setActiveLine("Brain")

        let done = DispatchSemaphore(value: 0)
        var enqueued: NativeRelay?
        var enqueueError: Error?
        DispatchQueue.global().async {
            do {
                enqueued = try store.enqueue(NewRelayInput(line: "Other", message: "first inactive", type: "update", priority: "normal", session: nil, app: nil, cwd: nil, url: nil))
            } catch {
                enqueueError = error
            }
            done.signal()
        }

        try waitForFile(atPath: startedPath)
        store.setActiveLine("Other")
        FileManager.default.createFile(atPath: releasePath, contents: Data())
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
        XCTAssertNil(enqueueError)
        XCTAssertEqual(enqueued?.message, "first inactive")
        XCTAssertEqual(store.recentMessages(line: "Other").map(\.message), ["first inactive"])
    }

    private func testArtifactDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".test-artifacts", isDirectory: true)
    }
}

private final class DatabaseSnapshot {
    private let database: OpaquePointer

    init(path: String) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let opened else {
            throw NSError(domain: "DatabaseSnapshot", code: 1)
        }
        database = opened
    }

    deinit {
        sqlite3_close(database)
    }

    func execute(_ sql: String) {
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    func scalar(_ sql: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let columnType = sqlite3_column_type(statement, 0)

        if columnType == SQLITE_NULL {
            return nil
        }

        if columnType == SQLITE_INTEGER {
            return String(sqlite3_column_int64(statement, 0))
        }

        return String(cString: sqlite3_column_text(statement, 0))
    }
}

private func inactiveCombinerScript(outputMessage: String) throws -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tsrs-combiner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("combiner").path
    let escapedMessage = outputMessage.replacingOccurrences(of: "'", with: "'\\''")
    let body = """
    #!/bin/sh
    printf '%s\\n' '{"action":"replace","type":"update","priority":"normal","message":"\(escapedMessage)"}'
    """
    try body.write(toFile: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
    return script
}

private func blockingInactiveCombinerScript(outputMessage: String, startedPath: String, releasePath: String) throws -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tsrs-combiner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("combiner").path
    let escapedMessage = outputMessage.replacingOccurrences(of: "'", with: "'\\''")
    let body = """
    #!/bin/sh
    : > '\(startedPath)'
    while [ ! -f '\(releasePath)' ]; do sleep 0.05; done
    printf '%s\\n' '{"action":"replace","type":"update","priority":"normal","message":"\(escapedMessage)"}'
    """
    try body.write(toFile: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
    return script
}

private func waitForFile(atPath path: String) throws {
    let deadline = Date().addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: path) {
        if Date() > deadline {
            XCTFail("timed out waiting for \(path)")
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
}
