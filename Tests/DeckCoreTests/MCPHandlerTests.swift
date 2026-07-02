import Foundation
import Testing
@testable import DeckCore

struct MCPHandlerTests {
    let repository: Repository
    let handler: MCPHandler

    init() throws {
        repository = Repository(database: try AppDatabase.inMemory())
        handler = MCPHandler(repository: repository)
    }

    // MARK: - Helpers

    @discardableResult
    func rpc(_ method: String, params: [String: JSONValue] = [:], id: JSONValue? = .int(1)) -> JSONValue? {
        var message: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": .object(params),
        ]
        if let id { message["id"] = id }
        let response = handler.handlePost(body: JSONValue.object(message).serialized())
        guard let body = response.body else { return nil }
        return try? JSONValue.parse(body)
    }

    /// Calls a tool and returns the decoded text payload plus the isError flag.
    func callTool(_ name: String, _ arguments: [String: JSONValue] = [:]) -> (payload: JSONValue?, isError: Bool, text: String) {
        let response = rpc("tools/call", params: [
            "name": .string(name),
            "arguments": .object(arguments),
        ])
        let result = response?["result"]
        let text = result?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        let isError = result?["isError"]?.boolValue ?? false
        let payload = try? JSONValue.parse(Data(text.utf8))
        return (payload, isError, text)
    }

    // MARK: - Protocol plumbing

    @Test func initializeHandshake() {
        let response = rpc("initialize", params: [
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("claude-code"), "version": .string("2.0")]),
        ])
        let result = response?["result"]
        #expect(result?["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(result?["serverInfo"]?["name"]?.stringValue == "deck")
        #expect(result?["capabilities"]?["tools"] != nil)
        #expect(result?["instructions"]?.stringValue != nil)
    }

    @Test func unsupportedProtocolVersionFallsBack() {
        let response = rpc("initialize", params: ["protocolVersion": .string("1999-01-01")])
        #expect(response?["result"]?["protocolVersion"]?.stringValue == "2025-03-26")
    }

    @Test func notificationGets202() {
        let response = handler.handlePost(body: Data(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8
        ))
        #expect(response.status == 202)
        #expect(response.body == nil)
    }

    @Test func parseErrorGets400() {
        let response = handler.handlePost(body: Data("not json".utf8))
        #expect(response.status == 400)
    }

    @Test func unknownMethodReturnsMethodNotFound() {
        let response = rpc("resources/list")
        #expect(response?["error"]?["code"]?.intValue == -32601)
    }

    @Test func toolsListExposesAllTools() {
        let response = rpc("tools/list")
        let tools = response?["result"]?["tools"]?.arrayValue ?? []
        let names = tools.compactMap { $0["name"]?.stringValue }
        #expect(names.contains("create_ticket"))
        #expect(names.contains("search_tickets"))
        #expect(names.contains("reorder_columns"))
        #expect(names.count == 15)
        for tool in tools {
            #expect(tool["inputSchema"]?["type"] != nil, "every tool needs a schema")
            let description = tool["description"]?.stringValue ?? ""
            #expect(description.isEmpty == false)
        }
    }

    // MARK: - Tool behavior

    @Test func createProjectAndTicketViaCwd() {
        let created = callTool("create_project", [
            "name": .string("Ankify"),
            "path": .string("/tmp/ankify"),
        ])
        #expect(!created.isError)

        let ticket = callTool("create_ticket", [
            "cwd": .string("/tmp/ankify/src/deep"),
            "title": .string("Support cloze cards"),
            "description": .string("Idea from session"),
            "priority": .string("medium"),
            "tags": .array([.string("idea")]),
        ])
        #expect(!ticket.isError)
        #expect(ticket.payload?["project"]?.stringValue == "Ankify")
        #expect(ticket.payload?["column"]?.stringValue == "Ideas")
        #expect(ticket.payload?["priority"]?.stringValue == "medium")
    }

    @Test func unknownCwdIsHelpfulError() {
        _ = callTool("create_project", ["name": .string("Ankify"), "path": .string("/tmp/ankify")])
        let result = callTool("create_ticket", [
            "cwd": .string("/tmp/mystery"),
            "title": .string("T"),
        ])
        #expect(result.isError)
        #expect(result.text.contains("Ankify"), "error should list known projects: \(result.text)")
        #expect(result.text.contains("create_project"))
    }

    @Test func fullTicketLifecycle() {
        _ = callTool("create_project", ["name": .string("P"), "path": .string("/tmp/p")])
        let created = callTool("create_ticket", [
            "cwd": .string("/tmp/p"),
            "title": .string("Ship it"),
        ])
        let id = created.payload?["id"]?.intValue ?? -1

        let moved = callTool("move_ticket", [
            "id": .int(id),
            "column": .string("In Progress"),
        ])
        #expect(moved.payload?["column"]?.stringValue == "In Progress")

        let noted = callTool("add_note", [
            "id": .int(id),
            "body": .string("Half way through, found a snag."),
        ])
        #expect(noted.payload?["notes"]?.arrayValue?.count == 1)
        #expect(noted.payload?["notes"]?.arrayValue?.first?["author"]?.stringValue == "agent")

        let updated = callTool("update_ticket", [
            "id": .int(id),
            "priority": .string("high"),
        ])
        #expect(updated.payload?["priority"]?.stringValue == "high")

        let deleted = callTool("delete_ticket", ["id": .int(id)])
        #expect(deleted.payload?["deleted"]?.boolValue == true)

        let restored = callTool("restore_ticket", ["id": .int(id)])
        #expect(restored.payload?["column"]?.stringValue == "In Progress")

        let board = callTool("get_board", ["cwd": .string("/tmp/p")])
        let columns = board.payload?["columns"]?.arrayValue ?? []
        let inProgress = columns.first { $0["name"]?.stringValue == "In Progress" }
        #expect(inProgress?["tickets"]?.arrayValue?.count == 1)
    }

    @Test func columnManagementViaTools() {
        _ = callTool("create_project", ["name": .string("P"), "path": .string("/tmp/p")])
        _ = callTool("add_column", ["cwd": .string("/tmp/p"), "name": .string("Blocked")])
        _ = callTool("rename_column", ["cwd": .string("/tmp/p"), "from": .string("Ideas"), "to": .string("Inbox")])

        let reordered = callTool("reorder_columns", [
            "cwd": .string("/tmp/p"),
            "order": .array([.string("Blocked"), .string("Inbox"), .string("Backlog"), .string("In Progress"), .string("Done")]),
        ])
        let names = reordered.payload?["columns"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        #expect(names == ["Blocked", "Inbox", "Backlog", "In Progress", "Done"])

        let deleted = callTool("delete_column", [
            "cwd": .string("/tmp/p"),
            "name": .string("Blocked"),
        ])
        #expect(!deleted.isError)
    }

    @Test func searchToolFindsNotes() {
        _ = callTool("create_project", ["name": .string("P"), "path": .string("/tmp/p")])
        let created = callTool("create_ticket", ["cwd": .string("/tmp/p"), "title": .string("Quiet title")])
        let id = created.payload?["id"]?.intValue ?? -1
        _ = callTool("add_note", ["id": .int(id), "body": .string("mentions zebras explicitly")])

        let hits = callTool("search_tickets", ["query": .string("zebras")])
        #expect(hits.payload?.arrayValue?.count == 1)
        #expect(hits.payload?.arrayValue?.first?["id"]?.intValue == id)
    }

    @Test func invalidPriorityIsToolError() {
        _ = callTool("create_project", ["name": .string("P"), "path": .string("/tmp/p")])
        let result = callTool("create_ticket", [
            "cwd": .string("/tmp/p"),
            "title": .string("T"),
            "priority": .string("mega"),
        ])
        #expect(result.isError)
        #expect(result.text.contains("urgent"))
    }

    @Test func unknownToolListsAvailable() {
        let result = callTool("do_magic")
        #expect(result.isError)
        #expect(result.text.contains("create_ticket"))
    }
}
