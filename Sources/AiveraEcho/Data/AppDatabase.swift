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

    /// File-backed database in the app's Documents directory.
    static func makeShared() throws -> AppDatabase {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("echo.sqlite")

        var config = Configuration()
        config.label = "AiveraEcho"
        // foreignKeysEnabled is on by default; explicit for clarity.
        config.foreignKeysEnabled = true

        // M2.2 will set config.prepareDatabase here to plug in SQLCipher.
        let pool = try DatabasePool(path: url.path, configuration: config)
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

        return migrator
    }
}
