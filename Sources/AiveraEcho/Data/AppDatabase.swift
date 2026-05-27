import Foundation
import GRDB

/// Holds the app's SQLite database (via GRDB's DatabasePool — supports concurrent
/// reads with one writer). M2.1 ships plaintext; M2.2 swaps in SQLCipher with
/// a key stored in the iOS Keychain (mirror of Android's `DatabaseKey`).
final class AppDatabase {

    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// File-backed database in `~/Documents/database/echo.sqlite`. Encrypted
    /// at rest via iOS Data Protection — applied to the parent directory so
    /// SQLite's lazily-created WAL/SHM/journal sidecars inherit it automatically.
    static func makeShared() throws -> AppDatabase {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dbDir = docs.appendingPathComponent("database", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        // Apply protection to the directory: anything created inside inherits.
        // No async dance needed, no race vs. SQLite's lazy WAL creation.
        FileProtection.apply(to: dbDir)

        let url = dbDir.appendingPathComponent("echo.sqlite")

        var config = Configuration()
        config.label = "AiveraEcho"
        config.foreignKeysEnabled = true

        let pool = try DatabasePool(path: url.path, configuration: config)

        // Belt + braces: also explicitly protect the SQLite file itself once it exists.
        FileProtection.apply(to: url)

        return try AppDatabase(pool)
    }

    /// In-memory database for previews + tests.
    static func makeEphemeral() throws -> AppDatabase {
        let queue = try DatabaseQueue() // in-memory
        return try AppDatabase(queue)
    }

    // MARK: - Migrations
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1.create_reminders") { db in
            try db.create(table: Reminder.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("clientId", .text).notNull()
                t.column("text", .text).notNull()
                t.column("triggerAt", .datetime).notNull()
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("completedAt", .datetime)
                t.column("audioPath", .text)
                t.column("recurrence", .text).notNull().defaults(to: Recurrence.none.rawValue)
                t.column("triggerType", .text).notNull().defaults(to: TriggerType.time.rawValue)
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("radiusMeters", .double)
                t.column("placeLabel", .text)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_reminders_completed_triggerAt",
                on: Reminder.databaseTableName,
                columns: ["completed", "triggerAt"]
            )
        }

        // v2: sync metadata. `dirty` = needs push; `pendingDelete` = tombstone.
        migrator.registerMigration("v2.add_sync_fields") { db in
            try db.alter(table: Reminder.databaseTableName) { t in
                t.add(column: "dirty", .boolean).notNull().defaults(to: false)
                t.add(column: "pendingDelete", .boolean).notNull().defaults(to: false)
            }
            try db.create(
                index: "idx_reminders_dirty",
                on: Reminder.databaseTableName,
                columns: ["dirty"]
            )
        }

        return migrator
    }
}
