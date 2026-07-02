import Foundation
import Testing
@testable import DeckCore

struct RepositoryTests {
    let repository: Repository

    init() throws {
        repository = Repository(database: try AppDatabase.inMemory())
    }

    @discardableResult
    func makeProject(name: String = "Ankify", path: String = "/Users/me/dev/ankify") throws -> Project {
        try repository.createProject(name: name, paths: [path])
    }

    // MARK: - Projects

    @Test func createProjectWithDefaultColumns() throws {
        let project = try makeProject()
        let columns = try repository.columns(projectId: project.id!)
        #expect(columns.map(\.name) == ["Ideas", "Backlog", "In Progress", "Done"])
    }

    @Test func duplicateProjectNameRejectedCaseInsensitively() throws {
        try makeProject(name: "Ankify")
        #expect(throws: DeckError.projectNameTaken("ankify")) {
            try repository.createProject(name: "ankify")
        }
    }

    @Test func resolveByExplicitNameBeatsCwd() throws {
        let a = try makeProject(name: "A", path: "/tmp/a")
        try makeProject(name: "B", path: "/tmp/b")
        let resolved = try repository.resolveProject(name: "a", cwd: "/tmp/b")
        #expect(resolved.id == a.id)
    }

    @Test func resolveByCwdPicksLongestPrefix() throws {
        let outer = try makeProject(name: "Outer", path: "/Users/me/dev")
        let inner = try makeProject(name: "Inner", path: "/Users/me/dev/ankify")

        let inInner = try repository.resolveProject(name: nil, cwd: "/Users/me/dev/ankify/Sources")
        #expect(inInner.id == inner.id)

        let inOuter = try repository.resolveProject(name: nil, cwd: "/Users/me/dev/other")
        #expect(inOuter.id == outer.id)
    }

    @Test func resolvePrefixMatchesWholeComponentsOnly() throws {
        try makeProject(name: "Ankify", path: "/Users/me/dev/ankify")
        #expect(throws: DeckError.self) {
            try repository.resolveProject(name: nil, cwd: "/Users/me/dev/ankify-fork")
        }
    }

    @Test func resolveUnknownCwdListsProjects() throws {
        try makeProject()
        do {
            _ = try repository.resolveProject(name: nil, cwd: "/somewhere/else")
            Issue.record("expected an error")
        } catch let error as DeckError {
            guard case let .noProjectForPath(_, available) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(available == ["Ankify"])
        }
    }

    @Test func pathNormalizationExpandsTildeAndTrailingSlash() {
        #expect(ProjectPath.normalize("~/dev/thing/") == NSHomeDirectory() + "/dev/thing")
    }

    @Test func deleteProjectRemovesTicketsAndColumns() throws {
        let project = try makeProject()
        _ = try repository.createTicket(projectId: project.id!, title: "T")
        try repository.deleteProject(id: project.id!)
        #expect(try repository.projects().isEmpty)
    }

    // MARK: - Columns

    @Test func columnLifecycle() throws {
        let project = try makeProject()
        try repository.addColumn(projectId: project.id!, name: "Blocked")
        try repository.renameColumn(projectId: project.id!, from: "blocked", to: "Waiting")
        try repository.reorderColumns(
            projectId: project.id!,
            orderedNames: ["Waiting", "Done", "In Progress", "Backlog", "Ideas"]
        )
        let columns = try repository.columns(projectId: project.id!)
        #expect(columns.map(\.name) == ["Waiting", "Done", "In Progress", "Backlog", "Ideas"])
    }

    @Test func deleteColumnRequiresTargetWhenOccupied() throws {
        let project = try makeProject()
        let ticket = try repository.createTicket(projectId: project.id!, columnName: "Backlog", title: "T")

        #expect(throws: DeckError.self) {
            try repository.deleteColumn(projectId: project.id!, name: "Backlog", moveTicketsTo: nil)
        }

        try repository.deleteColumn(projectId: project.id!, name: "Backlog", moveTicketsTo: "Ideas")
        let detail = try repository.ticketDetail(id: ticket.id!)
        #expect(detail.columnName == "Ideas")
    }

    @Test func cannotDeleteLastColumn() throws {
        let project = try repository.createProject(name: "One", columnNames: ["Only"])
        #expect(throws: DeckError.lastColumn) {
            try repository.deleteColumn(projectId: project.id!, name: "Only", moveTicketsTo: nil)
        }
    }

    // MARK: - Tickets

    @Test func newTicketsLandAtTopOfFirstColumn() throws {
        let project = try makeProject()
        let first = try repository.createTicket(projectId: project.id!, title: "first")
        let second = try repository.createTicket(projectId: project.id!, title: "second")

        let board = try repository.board(projectId: project.id!)
        #expect(board[0].column.name == "Ideas")
        #expect(board[0].tickets.map(\.id) == [second.id, first.id])
    }

    @Test func moveTicketTopAndBottom() throws {
        let project = try makeProject()
        let a = try repository.createTicket(projectId: project.id!, title: "a")
        let b = try repository.createTicket(projectId: project.id!, title: "b")

        _ = try repository.moveTicket(id: a.id!, toColumnNamed: "in progress")
        _ = try repository.moveTicket(id: b.id!, toColumnNamed: "In Progress", placement: .bottom)

        let board = try repository.board(projectId: project.id!)
        let inProgress = board.first { $0.column.name == "In Progress" }!
        #expect(inProgress.tickets.map(\.title) == ["a", "b"])
    }

    @Test func softDeleteRestoreAndPurge() throws {
        let project = try makeProject()
        let ticket = try repository.createTicket(projectId: project.id!, title: "doomed")

        _ = try repository.softDeleteTicket(id: ticket.id!)
        #expect(try repository.board(projectId: project.id!)[0].tickets.isEmpty)
        #expect(try repository.trash(projectId: project.id!).count == 1)

        _ = try repository.restoreTicket(id: ticket.id!)
        #expect(try repository.board(projectId: project.id!)[0].tickets.count == 1)

        _ = try repository.softDeleteTicket(id: ticket.id!)
        #expect(try repository.purgeTrash(olderThanDays: 30) == 0, "fresh trash survives the purge")
        #expect(try repository.purgeTrash(olderThanDays: -1) == 1, "old trash is purged")
        #expect(throws: DeckError.ticketNotFound(ticket.id!)) {
            try repository.ticketDetail(id: ticket.id!)
        }
    }

    @Test func tagsAreDeduplicatedAndTrimmed() throws {
        let project = try makeProject()
        let ticket = try repository.createTicket(
            projectId: project.id!,
            title: "T",
            tags: [" bug ", "Bug", "mcp", ""]
        )
        #expect(ticket.tagList == ["bug", "mcp"])
    }

    @Test func updateTicketPartialFields() throws {
        let project = try makeProject()
        let ticket = try repository.createTicket(projectId: project.id!, title: "T", details: "body")
        let updated = try repository.updateTicket(id: ticket.id!, priority: .high)
        #expect(updated.title == "T")
        #expect(updated.details == "body")
        #expect(updated.priority == .high)
    }

    // MARK: - Notes & search

    @Test func notesAppendInOrder() throws {
        let project = try makeProject()
        let ticket = try repository.createTicket(projectId: project.id!, title: "T")
        _ = try repository.addNote(ticketId: ticket.id!, author: "agent", body: "first finding")
        _ = try repository.addNote(ticketId: ticket.id!, author: "me", body: "second thought")

        let detail = try repository.ticketDetail(id: ticket.id!)
        #expect(detail.notes.map(\.body) == ["first finding", "second thought"])
        #expect(detail.notes.map(\.author) == ["agent", "me"])
    }

    @Test func searchCoversTitleDetailsTagsAndNotes() throws {
        let project = try makeProject()
        let byTitle = try repository.createTicket(projectId: project.id!, title: "Fix MCP timeout")
        let byDetails = try repository.createTicket(projectId: project.id!, title: "Other", details: "the mcp server hangs")
        let byTag = try repository.createTicket(projectId: project.id!, title: "Tagged", tags: ["mcp"])
        let byNote = try repository.createTicket(projectId: project.id!, title: "Noted")
        _ = try repository.addNote(ticketId: byNote.id!, author: "agent", body: "relates to MCP retries")
        _ = try repository.createTicket(projectId: project.id!, title: "Unrelated")

        let hits = try repository.search(query: "mcp")
        #expect(Set(hits.map { $0.ticket.id! }) == Set([byTitle.id!, byDetails.id!, byTag.id!, byNote.id!]))
    }

    @Test func searchEscapesLikeWildcards() throws {
        let project = try makeProject()
        _ = try repository.createTicket(projectId: project.id!, title: "100% done")
        _ = try repository.createTicket(projectId: project.id!, title: "100 percent")
        let hits = try repository.search(query: "100%")
        #expect(hits.map { $0.ticket.title } == ["100% done"])
    }

    @Test func searchScopedToProject() throws {
        let a = try makeProject(name: "A", path: "/tmp/aa")
        let b = try makeProject(name: "B", path: "/tmp/bb")
        _ = try repository.createTicket(projectId: a.id!, title: "shared term")
        _ = try repository.createTicket(projectId: b.id!, title: "shared term")

        let hits = try repository.search(query: "shared", projectId: a.id)
        #expect(hits.count == 1)
        #expect(hits.first?.projectName == "A")
    }
}
