import Foundation
import GRDB

public struct AppDatabase {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// Opens (creating if needed) the on-disk database in Application Support.
    public static func onDisk() throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support.appendingPathComponent("Deck", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dbQueue = try DatabaseQueue(path: folder.appendingPathComponent("deck.sqlite").path)
        return try AppDatabase(dbQueue: dbQueue)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(dbQueue: DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().collate(.nocase).unique()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "projectPath") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("path", .text).notNull().unique()
            }

            try db.create(table: "boardColumn") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("name", .text).notNull().collate(.nocase)
                t.column("position", .double).notNull()
                t.uniqueKey(["projectId", "name"])
            }

            try db.create(table: "ticket") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("columnId", .integer).notNull().indexed()
                    .references("boardColumn", onDelete: .restrict)
                t.column("title", .text).notNull()
                t.column("details", .text).notNull().defaults(to: "")
                t.column("priority", .text).notNull().defaults(to: "none")
                t.column("tags", .text).notNull().defaults(to: "")
                t.column("position", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(indexOn: "ticket", columns: ["projectId", "deletedAt"])

            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("ticket", onDelete: .cascade).notNull()
                t.column("author", .text).notNull()
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        return migrator
    }
}
