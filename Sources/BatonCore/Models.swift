import Foundation
import GRDB

public struct Project: Codable, Identifiable, Equatable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "project"

    public var id: Int64?
    public var name: String
    public var createdAt: Date

    public init(id: Int64? = nil, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ProjectPath: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "projectPath"

    public var id: Int64?
    public var projectId: Int64
    public var path: String

    public init(id: Int64? = nil, projectId: Int64, path: String) {
        self.id = id
        self.projectId = projectId
        self.path = path
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Expands ~ and standardizes the path so prefix matching is reliable.
    public static func normalize(_ raw: String) -> String {
        let expanded = (raw as NSString).expandingTildeInPath
        var path = URL(fileURLWithPath: expanded).standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

public struct BoardColumn: Codable, Identifiable, Equatable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "boardColumn"

    public var id: Int64?
    public var projectId: Int64
    public var name: String
    public var position: Double

    public init(id: Int64? = nil, projectId: Int64, name: String, position: Double) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.position = position
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum TicketPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case none
    case low
    case medium
    case high
    case urgent

    public var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .urgent: return 4
        }
    }

    public static func < (lhs: TicketPriority, rhs: TicketPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct Ticket: Codable, Identifiable, Equatable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "ticket"

    public var id: Int64?
    public var projectId: Int64
    public var columnId: Int64
    public var title: String
    public var details: String
    public var priority: TicketPriority
    /// Comma-separated tags.
    public var tags: String
    public var position: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: Int64? = nil,
        projectId: Int64,
        columnId: Int64,
        title: String,
        details: String = "",
        priority: TicketPriority = .none,
        tags: String = "",
        position: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.columnId = columnId
        self.title = title
        self.details = details
        self.priority = priority
        self.tags = tags
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var tagList: [String] {
        get {
            tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            tags = Ticket.joinTags(newValue)
        }
    }

    public static func joinTags(_ list: [String]) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for raw in list {
            let tag = raw.trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            result.append(tag)
        }
        return result.joined(separator: ",")
    }
}

public struct Note: Codable, Identifiable, Equatable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "note"

    public var id: Int64?
    public var ticketId: Int64
    public var author: String
    public var body: String
    public var createdAt: Date

    public init(id: Int64? = nil, ticketId: Int64, author: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.ticketId = ticketId
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
