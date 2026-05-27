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

    /// File-backed database in the app's Documents directory. Encrypted at rest
    /// via iOS Data Protection (see `FileProtection.swift`).
    static func makeShared() throws -> AppDatabase {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("echo.sqlite")

        var config = Configuration()
        config.label = "AiveraEcho"
        config.foreignKeysEnabled = true

        let pool = try DatabasePool(path: url.path, configuration: config)

        // Apply iOS Data Protection to the SQLite file + its sidecars. The WAL
        // and SHM files appear lazily on first write; apply once now and then
        // again on first write via `prepareDatabase` — see protectSidecarsLazily().
        FileProtection.apply(to: url)
        Self.protectSidecarsLazily(for: url, in: pool)

        return try AppDatabase(pool)
    }

    /// Schedule a one-off DB op that runs after the WAL/SHM sidecars exist,
    /// then apply the same file protection class to them.
    private static func protectSidecarsLazily(for dbURL: URL, in pool: DatabasePool) {
        Task.detached(priority: .background) {
            // A trivial read forces SQLite to materialise the WAL/SHM files.
            try? pool.read { _ in }
            await MainActor.run {
                let sidecars = [
                    dbURL.appendingPathExtension("wal"),
                    dbURL.appendingPathExtension("shm"),
                    dbURL.appendingPathExtension("journal"),
                ]
                sidecars.forEach { FileProtection.apply(to: $0) }
            }
        }
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
