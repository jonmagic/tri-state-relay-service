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
        XCTAssertEqual(database.scalar("SELECT value FROM settings WHERE key = 'first_start_setup_complete'"), "false")
        XCTAssertEqual(database.scalar("SELECT version FROM schema_migrations WHERE version = 1"), "1")
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
        store.saveCommandPaletteShortcut(KeyboardShortcut(identifier: "control-option-command-p"))

        XCTAssertEqual(NativeRelayStore(profile: "direct").loadSettings().commandPaletteShortcut.identifier, "control-option-command-p")
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
