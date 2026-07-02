import Foundation

public enum DeckError: Error, LocalizedError, Equatable {
    case projectNotFound(name: String, available: [String])
    case noProjectForPath(cwd: String, available: [String])
    case projectRequired(available: [String])
    case projectNameTaken(String)
    case columnNotFound(name: String, available: [String])
    case columnNameTaken(String)
    case columnNotEmpty(name: String, ticketCount: Int)
    case lastColumn
    case ticketNotFound(Int64)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case let .projectNotFound(name, available):
            return "No project named '\(name)'. Known projects: \(Self.list(available)). Use create_project to add one."
        case let .noProjectForPath(cwd, available):
            return "No project is registered for path '\(cwd)'. Known projects: \(Self.list(available)). Pass an explicit project name, or ask the user whether to register this folder with create_project."
        case let .projectRequired(available):
            return "A project is required. Pass 'project' or 'cwd'. Known projects: \(Self.list(available))."
        case let .projectNameTaken(name):
            return "A project named '\(name)' already exists."
        case let .columnNotFound(name, available):
            return "No column named '\(name)' on this board. Columns: \(Self.list(available))."
        case let .columnNameTaken(name):
            return "A column named '\(name)' already exists on this board."
        case let .columnNotEmpty(name, count):
            return "Column '\(name)' still contains \(count) ticket(s). Pass move_tickets_to with a target column."
        case .lastColumn:
            return "Cannot delete the last remaining column."
        case let .ticketNotFound(id):
            return "No ticket with id \(id)."
        case let .invalidInput(message):
            return message
        }
    }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "(none yet)" : names.joined(separator: ", ")
    }
}
