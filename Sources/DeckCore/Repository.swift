import Foundation
import GRDB

public extension Notification.Name {
    /// Posted (on the main queue) after any write to the Deck database.
    static let deckDataDidChange = Notification.Name("deckDataDidChange")
}

public struct ProjectDetail: Identifiable, Equatable {
    public var project: Project
    public var paths: [ProjectPath]
    public var columns: [BoardColumn]
    public var ticketCount: Int
    public var trashCount: Int

    public var id: Int64? { project.id }
}

public struct ColumnTickets: Identifiable, Equatable {
    public var column: BoardColumn
    public var tickets: [Ticket]

    public var id: Int64? { column.id }
}

public struct TicketDetail: Equatable {
    public var ticket: Ticket
    public var projectName: String
    public var columnName: String
    public var notes: [Note]
}

public struct SearchHit: Identifiable, Equatable {
    public var ticket: Ticket
    public var projectName: String
    public var columnName: String

    public var id: Int64? { ticket.id }
}

public enum TicketPlacement {
    case top
    case bottom
}

public final class Repository {
    public static let defaultColumnNames = ["Ideas", "Backlog", "In Progress", "Done"]
    static let positionGap: Double = 1024

    let dbQueue: DatabaseQueue

    public init(database: AppDatabase) {
        self.dbQueue = database.dbQueue
    }

    // MARK: - Projects

    @discardableResult
    public func createProject(name: String, paths: [String] = [], columnNames: [String]? = nil) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeckError.invalidInput("Project name cannot be empty.") }

        var requestedColumns = (columnNames ?? Self.defaultColumnNames)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if requestedColumns.isEmpty {
            requestedColumns = Self.defaultColumnNames
        }
        guard Set(requestedColumns.map { $0.lowercased() }).count == requestedColumns.count else {
            throw DeckError.invalidInput("Column names must be unique.")
        }

        let project = try write { db in
            if try Project.filter(Column("name") == trimmed).fetchOne(db) != nil {
                throw DeckError.projectNameTaken(trimmed)
            }
            var project = Project(name: trimmed)
            try project.insert(db)

            for (index, columnName) in requestedColumns.enumerated() {
                var column = BoardColumn(
                    projectId: project.id!,
                    name: columnName,
                    position: Double(index + 1) * Self.positionGap
                )
                try column.insert(db)
            }

            for raw in paths {
                let normalized = ProjectPath.normalize(raw)
                guard !normalized.isEmpty else { continue }
                if try ProjectPath.filter(Column("path") == normalized).fetchOne(db) != nil {
                    throw DeckError.invalidInput("Path '\(normalized)' is already registered to another project.")
                }
                var projectPath = ProjectPath(projectId: project.id!, path: normalized)
                try projectPath.insert(db)
            }
            return project
        }
        return project
    }

    public func projects() throws -> [ProjectDetail] {
        try dbQueue.read { db in
            let projects = try Project.order(Column("name")).fetchAll(db)
            return try projects.map { project in
                ProjectDetail(
                    project: project,
                    paths: try ProjectPath
                        .filter(Column("projectId") == project.id!)
                        .order(Column("path"))
                        .fetchAll(db),
                    columns: try Self.orderedColumns(db, projectId: project.id!),
                    ticketCount: try Ticket
                        .filter(Column("projectId") == project.id! && Column("deletedAt") == nil)
                        .fetchCount(db),
                    trashCount: try Ticket
                        .filter(Column("projectId") == project.id! && Column("deletedAt") != nil)
                        .fetchCount(db)
                )
            }
        }
    }

    public func project(id: Int64) throws -> Project {
        try dbQueue.read { db in
            guard let project = try Project.fetchOne(db, key: id) else {
                throw DeckError.invalidInput("No project with id \(id).")
            }
            return project
        }
    }

    public func renameProject(id: Int64, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeckError.invalidInput("Project name cannot be empty.") }
        try write { db in
            if let existing = try Project.filter(Column("name") == trimmed).fetchOne(db), existing.id != id {
                throw DeckError.projectNameTaken(trimmed)
            }
            guard var project = try Project.fetchOne(db, key: id) else {
                throw DeckError.invalidInput("No project with id \(id).")
            }
            project.name = trimmed
            try project.update(db)
        }
    }

    public func deleteProject(id: Int64) throws {
        try write { db in
            // Tickets restrict column deletion, so clear them before the cascade.
            try Ticket.filter(Column("projectId") == id).deleteAll(db)
            try Project.deleteOne(db, key: id)
        }
    }

    @discardableResult
    public func addPath(projectId: Int64, path raw: String) throws -> ProjectPath {
        let normalized = ProjectPath.normalize(raw)
        guard !normalized.isEmpty, normalized != "/" else {
            throw DeckError.invalidInput("'\(raw)' is not a usable project path.")
        }
        return try write { db in
            if let existing = try ProjectPath.filter(Column("path") == normalized).fetchOne(db) {
                let owner = try Project.fetchOne(db, key: existing.projectId)?.name ?? "?"
                throw DeckError.invalidInput("Path '\(normalized)' is already registered to project '\(owner)'.")
            }
            var projectPath = ProjectPath(projectId: projectId, path: normalized)
            try projectPath.insert(db)
            return projectPath
        }
    }

    public func removePath(id: Int64) throws {
        try write { db in
            try ProjectPath.deleteOne(db, key: id)
        }
    }

    /// Resolves a project from an explicit name and/or a session working directory.
    /// Explicit name wins; otherwise the registered path that is the longest
    /// prefix of `cwd` wins.
    public func resolveProject(name: String?, cwd: String?) throws -> Project {
        try dbQueue.read { db in
            let available = try Project.order(Column("name")).fetchAll(db).map(\.name)

            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard let project = try Project.filter(Column("name") == trimmed).fetchOne(db) else {
                    throw DeckError.projectNotFound(name: trimmed, available: available)
                }
                return project
            }

            if let cwd, !cwd.trimmingCharacters(in: .whitespaces).isEmpty {
                let normalizedCwd = ProjectPath.normalize(cwd)
                let allPaths = try ProjectPath.fetchAll(db)
                let best = allPaths
                    .filter { normalizedCwd == $0.path || normalizedCwd.hasPrefix($0.path + "/") }
                    .max { $0.path.count < $1.path.count }
                guard let best, let project = try Project.fetchOne(db, key: best.projectId) else {
                    throw DeckError.noProjectForPath(cwd: normalizedCwd, available: available)
                }
                return project
            }

            throw DeckError.projectRequired(available: available)
        }
    }

    // MARK: - Columns

    public func columns(projectId: Int64) throws -> [BoardColumn] {
        try dbQueue.read { db in
            try Self.orderedColumns(db, projectId: projectId)
        }
    }

    @discardableResult
    public func addColumn(projectId: Int64, name: String) throws -> BoardColumn {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeckError.invalidInput("Column name cannot be empty.") }
        return try write { db in
            let existing = try Self.orderedColumns(db, projectId: projectId)
            if existing.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
                throw DeckError.columnNameTaken(trimmed)
            }
            let position = (existing.last?.position ?? 0) + Self.positionGap
            var column = BoardColumn(projectId: projectId, name: trimmed, position: position)
            try column.insert(db)
            return column
        }
    }

    public func renameColumn(projectId: Int64, from: String, to: String) throws {
        let trimmed = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeckError.invalidInput("Column name cannot be empty.") }
        try write { db in
            var column = try Self.column(db, projectId: projectId, named: from)
            let clash = try Self.orderedColumns(db, projectId: projectId)
                .contains { $0.id != column.id && $0.name.lowercased() == trimmed.lowercased() }
            if clash {
                throw DeckError.columnNameTaken(trimmed)
            }
            column.name = trimmed
            try column.update(db)
        }
    }

    public func deleteColumn(projectId: Int64, name: String, moveTicketsTo: String?) throws {
        try write { db in
            let column = try Self.column(db, projectId: projectId, named: name)
            let all = try Self.orderedColumns(db, projectId: projectId)
            guard all.count > 1 else { throw DeckError.lastColumn }

            let residents = try Ticket.filter(Column("columnId") == column.id!).fetchAll(db)
            if !residents.isEmpty {
                guard let targetName = moveTicketsTo else {
                    let liveCount = residents.filter { $0.deletedAt == nil }.count
                    throw DeckError.columnNotEmpty(name: column.name, ticketCount: max(liveCount, residents.count))
                }
                let target = try Self.column(db, projectId: projectId, named: targetName)
                guard target.id != column.id else {
                    throw DeckError.invalidInput("Cannot move tickets into the column being deleted.")
                }
                var nextPosition = try Self.bottomPosition(db, columnId: target.id!)
                for var ticket in residents.sorted(by: { $0.position < $1.position }) {
                    ticket.columnId = target.id!
                    ticket.position = nextPosition
                    try ticket.update(db)
                    nextPosition += Self.positionGap
                }
            }
            try column.delete(db)
        }
    }

    public func reorderColumns(projectId: Int64, orderedNames: [String]) throws {
        try write { db in
            let existing = try Self.orderedColumns(db, projectId: projectId)
            let byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name.lowercased(), $0) })
            let requested = orderedNames.map { $0.trimmingCharacters(in: .whitespaces) }
            guard requested.count == existing.count,
                  Set(requested.map { $0.lowercased() }).count == existing.count,
                  requested.allSatisfy({ byName[$0.lowercased()] != nil })
            else {
                throw DeckError.invalidInput(
                    "order must list every column exactly once. Columns: \(existing.map(\.name).joined(separator: ", "))"
                )
            }
            for (index, name) in requested.enumerated() {
                var column = byName[name.lowercased()]!
                column.position = Double(index + 1) * Self.positionGap
                try column.update(db)
            }
        }
    }

    // MARK: - Board & tickets

    public func board(projectId: Int64) throws -> [ColumnTickets] {
        try dbQueue.read { db in
            let columns = try Self.orderedColumns(db, projectId: projectId)
            return try columns.map { column in
                ColumnTickets(
                    column: column,
                    tickets: try Ticket
                        .filter(Column("columnId") == column.id! && Column("deletedAt") == nil)
                        .order(Column("position"))
                        .fetchAll(db)
                )
            }
        }
    }

    @discardableResult
    public func createTicket(
        projectId: Int64,
        columnName: String? = nil,
        title: String,
        details: String = "",
        priority: TicketPriority = .none,
        tags: [String] = []
    ) throws -> Ticket {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DeckError.invalidInput("Ticket title cannot be empty.") }
        return try write { db in
            let column: BoardColumn
            if let columnName {
                column = try Self.column(db, projectId: projectId, named: columnName)
            } else {
                guard let first = try Self.orderedColumns(db, projectId: projectId).first else {
                    throw DeckError.invalidInput("Project has no columns.")
                }
                column = first
            }
            var ticket = Ticket(
                projectId: projectId,
                columnId: column.id!,
                title: trimmedTitle,
                details: details,
                priority: priority,
                tags: Ticket.joinTags(tags),
                position: try Self.topPosition(db, columnId: column.id!)
            )
            try ticket.insert(db)
            return ticket
        }
    }

    public func ticketDetail(id: Int64) throws -> TicketDetail {
        try dbQueue.read { db in
            guard let ticket = try Ticket.fetchOne(db, key: id) else {
                throw DeckError.ticketNotFound(id)
            }
            return TicketDetail(
                ticket: ticket,
                projectName: try Project.fetchOne(db, key: ticket.projectId)?.name ?? "?",
                columnName: try BoardColumn.fetchOne(db, key: ticket.columnId)?.name ?? "?",
                notes: try Note
                    .filter(Column("ticketId") == id)
                    .order(Column("createdAt"), Column("id"))
                    .fetchAll(db)
            )
        }
    }

    @discardableResult
    public func updateTicket(
        id: Int64,
        title: String? = nil,
        details: String? = nil,
        priority: TicketPriority? = nil,
        tags: [String]? = nil
    ) throws -> Ticket {
        try write { db in
            guard var ticket = try Ticket.fetchOne(db, key: id) else {
                throw DeckError.ticketNotFound(id)
            }
            if let title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw DeckError.invalidInput("Ticket title cannot be empty.") }
                ticket.title = trimmed
            }
            if let details { ticket.details = details }
            if let priority { ticket.priority = priority }
            if let tags { ticket.tagList = tags }
            ticket.updatedAt = Date()
            try ticket.update(db)
            return ticket
        }
    }

    @discardableResult
    public func moveTicket(id: Int64, toColumnNamed columnName: String, placement: TicketPlacement = .top) throws -> Ticket {
        try write { db in
            guard var ticket = try Ticket.fetchOne(db, key: id) else {
                throw DeckError.ticketNotFound(id)
            }
            let column = try Self.column(db, projectId: ticket.projectId, named: columnName)
            ticket.columnId = column.id!
            switch placement {
            case .top:
                ticket.position = try Self.topPosition(db, columnId: column.id!)
            case .bottom:
                ticket.position = try Self.bottomPosition(db, columnId: column.id!)
            }
            ticket.updatedAt = Date()
            try ticket.update(db)
            return ticket
        }
    }

    /// Precise placement for UI drag & drop.
    public func reorderTicket(id: Int64, toColumnId columnId: Int64, position: Double) throws {
        try write { db in
            guard var ticket = try Ticket.fetchOne(db, key: id) else {
                throw DeckError.ticketNotFound(id)
            }
            guard let column = try BoardColumn.fetchOne(db, key: columnId), column.projectId == ticket.projectId else {
                throw DeckError.invalidInput("Target column does not belong to the ticket's project.")
            }
            ticket.columnId = columnId
            ticket.position = position
            ticket.updatedAt = Date()
            try ticket.update(db)
        }
    }

    @discardableResult
    public func softDeleteTicket(id: Int64) throws -> Ticket {
        try write { db in
            guard var ticket = try Ticket.fetchOne(db, key: id) else {
                throw DeckError.ticketNotFound(id)
            }
            ticket.deletedAt = Date()
            ticket.updatedAt = Date()
            try ticket.update(db)
            return ticket
        }
    }

    @discardableResult
    public func restoreTicket(id: Int64) throws -> Ticket {
        try write { db in
            guard var ticket = try Ticket.fetchOne(db, key: id) else {
                throw DeckError.ticketNotFound(id)
            }
            ticket.deletedAt = nil
            ticket.updatedAt = Date()
            ticket.position = try Self.topPosition(db, columnId: ticket.columnId)
            try ticket.update(db)
            return ticket
        }
    }

    public func hardDeleteTicket(id: Int64) throws {
        try write { db in
            try Ticket.deleteOne(db, key: id)
        }
    }

    public func trash(projectId: Int64) throws -> [Ticket] {
        try dbQueue.read { db in
            try Ticket
                .filter(Column("projectId") == projectId && Column("deletedAt") != nil)
                .order(Column("deletedAt").desc)
                .fetchAll(db)
        }
    }

    /// Permanently removes trashed tickets older than `days`. Returns the purge count.
    @discardableResult
    public func purgeTrash(olderThanDays days: Int = 30) throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        return try write { db in
            try Ticket
                .filter(Column("deletedAt") != nil && Column("deletedAt") < cutoff)
                .deleteAll(db)
        }
    }

    // MARK: - Notes

    @discardableResult
    public func addNote(ticketId: Int64, author: String, body: String) throws -> Note {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeckError.invalidInput("Note body cannot be empty.") }
        return try write { db in
            guard var ticket = try Ticket.fetchOne(db, key: ticketId) else {
                throw DeckError.ticketNotFound(ticketId)
            }
            var note = Note(ticketId: ticketId, author: author, body: trimmed)
            try note.insert(db)
            ticket.updatedAt = Date()
            try ticket.update(db)
            return note
        }
    }

    // MARK: - Search

    public func search(query: String, projectId: Int64? = nil, includeTrashed: Bool = false) throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"

        return try dbQueue.read { db in
            var sql = """
                SELECT ticket.* FROM ticket
                WHERE (title LIKE :pattern ESCAPE '\\'
                    OR details LIKE :pattern ESCAPE '\\'
                    OR tags LIKE :pattern ESCAPE '\\'
                    OR EXISTS (
                        SELECT 1 FROM note
                        WHERE note.ticketId = ticket.id AND note.body LIKE :pattern ESCAPE '\\'
                    ))
                """
            var arguments: [String: (any DatabaseValueConvertible)?] = ["pattern": pattern]
            if !includeTrashed {
                sql += " AND deletedAt IS NULL"
            }
            if let projectId {
                sql += " AND projectId = :projectId"
                arguments["projectId"] = projectId
            }
            sql += " ORDER BY updatedAt DESC LIMIT 50"

            let tickets = try Ticket.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return try tickets.map { ticket in
                SearchHit(
                    ticket: ticket,
                    projectName: try Project.fetchOne(db, key: ticket.projectId)?.name ?? "?",
                    columnName: try BoardColumn.fetchOne(db, key: ticket.columnId)?.name ?? "?"
                )
            }
        }
    }

    // MARK: - Helpers

    static func orderedColumns(_ db: Database, projectId: Int64) throws -> [BoardColumn] {
        try BoardColumn
            .filter(Column("projectId") == projectId)
            .order(Column("position"))
            .fetchAll(db)
    }

    static func column(_ db: Database, projectId: Int64, named name: String) throws -> BoardColumn {
        let columns = try orderedColumns(db, projectId: projectId)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let column = columns.first(where: { $0.name.lowercased() == trimmed.lowercased() }) else {
            throw DeckError.columnNotFound(name: trimmed, available: columns.map(\.name))
        }
        return column
    }

    static func topPosition(_ db: Database, columnId: Int64) throws -> Double {
        let min = try Double.fetchOne(
            db,
            sql: "SELECT MIN(position) FROM ticket WHERE columnId = ?",
            arguments: [columnId]
        )
        return (min ?? positionGap * 2) - positionGap
    }

    static func bottomPosition(_ db: Database, columnId: Int64) throws -> Double {
        let max = try Double.fetchOne(
            db,
            sql: "SELECT MAX(position) FROM ticket WHERE columnId = ?",
            arguments: [columnId]
        )
        return (max ?? 0) + positionGap
    }

    @discardableResult
    private func write<T>(_ updates: @escaping (Database) throws -> T) throws -> T {
        let result = try dbQueue.write(updates)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .deckDataDidChange, object: nil)
        }
        return result
    }
}
