import AppKit
import Combine
import BatonCore
import SwiftUI

/// Identifiable wrapper so a ticket id can drive a sheet.
struct TicketSelection: Identifiable, Equatable {
    let id: Int64
}

@MainActor
final class AppStore: ObservableObject {
    let repository: Repository
    private var server: BatonServer?
    private var observer: NSObjectProtocol?

    @Published var projects: [ProjectDetail] = []
    @Published var selectedProjectId: Int64? {
        didSet { if oldValue != selectedProjectId { refreshBoard() } }
    }
    @Published var board: [ColumnTickets] = []
    @Published var openTicket: TicketSelection?
    @Published var newTicketRequested = false

    @Published var searchText = "" {
        didSet { if oldValue != searchText { refreshBoard() } }
    }
    @Published var priorityFilter: TicketPriority?
    @Published var tagFilter: String?

    @Published var errorMessage: String?
    @Published private(set) var serverError: String?

    private var searchMatchIds: Set<Int64>?

    init(repository: Repository) {
        self.repository = repository
        observer = NotificationCenter.default.addObserver(
            forName: .batonDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }

        attempt { try repository.purgeTrash() }
        refreshAll()
        selectedProjectId = projects.first?.project.id
        startServer()
    }

    var selectedProject: ProjectDetail? {
        projects.first { $0.project.id == selectedProjectId }
    }

    var mcpEndpoint: String {
        "http://127.0.0.1:\(BatonServer.defaultPort)/mcp"
    }

    // MARK: - Server

    private func startServer() {
        let server = BatonServer(mcp: MCPHandler(repository: repository))
        do {
            try server.start()
            self.server = server
            serverError = nil
        } catch {
            serverError = "MCP server failed to start on port \(BatonServer.defaultPort): \(error.localizedDescription). Is another copy of Baton running?"
        }
    }

    // MARK: - Refresh

    func refreshAll() {
        attempt { projects = try repository.projects() }
        if selectedProjectId == nil || !projects.contains(where: { $0.project.id == selectedProjectId }) {
            selectedProjectId = projects.first?.project.id
        }
        refreshBoard()
    }

    private func refreshBoard() {
        guard let projectId = selectedProjectId else {
            board = []
            searchMatchIds = nil
            return
        }
        attempt {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if query.isEmpty {
                searchMatchIds = nil
            } else {
                searchMatchIds = Set(try repository.search(query: query, projectId: projectId).compactMap(\.ticket.id))
            }
            board = try repository.board(projectId: projectId)
        }
    }

    /// Tickets of a column after search text and filters are applied.
    func visibleTickets(in columnTickets: ColumnTickets) -> [Ticket] {
        columnTickets.tickets.filter { ticket in
            if let searchMatchIds, !searchMatchIds.contains(ticket.id ?? -1) { return false }
            if let priorityFilter, ticket.priority != priorityFilter { return false }
            if let tagFilter, !ticket.tagList.contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) { return false }
            return true
        }
    }

    var allTags: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for columnTickets in board {
            for ticket in columnTickets.tickets {
                for tag in ticket.tagList where seen.insert(tag.lowercased()).inserted {
                    tags.append(tag)
                }
            }
        }
        return tags.sorted { $0.lowercased() < $1.lowercased() }
    }

    var filtersActive: Bool {
        priorityFilter != nil || tagFilter != nil
    }

    // MARK: - Projects

    func createProject(name: String, path: String?) {
        attempt {
            let project = try repository.createProject(name: name, paths: path.map { [$0] } ?? [])
            selectedProjectId = project.id
        }
    }

    func renameProject(id: Int64, to name: String) {
        attempt { try repository.renameProject(id: id, to: name) }
    }

    func deleteProject(id: Int64) {
        attempt { try repository.deleteProject(id: id) }
    }

    func addPath(projectId: Int64, path: String) {
        attempt { try repository.addPath(projectId: projectId, path: path) }
    }

    func removePath(id: Int64) {
        attempt { try repository.removePath(id: id) }
    }

    // MARK: - Columns

    func addColumn(name: String) {
        guard let projectId = selectedProjectId else { return }
        attempt { try repository.addColumn(projectId: projectId, name: name) }
    }

    func renameColumn(from: String, to: String) {
        guard let projectId = selectedProjectId else { return }
        attempt { try repository.renameColumn(projectId: projectId, from: from, to: to) }
    }

    func deleteColumn(name: String, moveTicketsTo: String?) {
        guard let projectId = selectedProjectId else { return }
        attempt { try repository.deleteColumn(projectId: projectId, name: name, moveTicketsTo: moveTicketsTo) }
    }

    func moveColumn(name: String, direction: Int) {
        guard let projectId = selectedProjectId else { return }
        attempt {
            var names = try repository.columns(projectId: projectId).map(\.name)
            guard let index = names.firstIndex(of: name) else { return }
            let target = index + direction
            guard names.indices.contains(target) else { return }
            names.swapAt(index, target)
            try repository.reorderColumns(projectId: projectId, orderedNames: names)
        }
    }

    // MARK: - Tickets

    func createTicket(columnName: String?, title: String, details: String, priority: TicketPriority, tags: [String]) {
        guard let projectId = selectedProjectId else { return }
        attempt {
            let ticket = try repository.createTicket(
                projectId: projectId,
                columnName: columnName,
                title: title,
                details: details,
                priority: priority,
                tags: tags
            )
            openTicket = ticket.id.map(TicketSelection.init)
        }
    }

    func trashTicket(id: Int64) {
        attempt { try repository.softDeleteTicket(id: id) }
        if openTicket?.id == id { openTicket = nil }
    }

    func restoreTicket(id: Int64) {
        attempt { try repository.restoreTicket(id: id) }
    }

    func hardDeleteTicket(id: Int64) {
        attempt { try repository.hardDeleteTicket(id: id) }
    }

    /// Handles a drag payload dropped before `target` (or at the bottom when nil).
    func dropTicket(payload: String, in column: BoardColumn, before target: Ticket?) {
        guard let ticketId = Int64(payload), let columnId = column.id else { return }
        guard let columnTickets = board.first(where: { $0.column.id == columnId })?.tickets else { return }

        var position: Double
        if let target, let index = columnTickets.firstIndex(where: { $0.id == target.id }) {
            if target.id == ticketId { return }
            let previous = index > 0 ? columnTickets[index - 1] : nil
            if previous?.id == ticketId { return }
            if let previous {
                position = (previous.position + target.position) / 2
            } else {
                position = target.position - 1024
            }
        } else {
            if columnTickets.last?.id == ticketId { return }
            position = (columnTickets.last?.position ?? 0) + 1024
        }
        attempt { try repository.reorderTicket(id: ticketId, toColumnId: columnId, position: position) }
    }

    // MARK: - Error funnel

    func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch let error as BatonError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
