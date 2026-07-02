import Foundation

/// Handles MCP JSON-RPC messages (streamable HTTP transport, tools only).
public final class MCPHandler {
    public static let serverName = "deck"
    public static let serverVersion = "1.0.0"
    static let supportedProtocolVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]
    static let defaultProtocolVersion = "2025-03-26"

    static let instructions = """
        Deck is the user's personal kanban board for tracking tickets/ideas across their \
        projects. Use it to defer ideas that come up while working (create_ticket into the \
        first column), record progress notes on tickets (add_note), and move tickets between \
        columns as work progresses. Always pass `cwd` (the absolute path of your session's \
        working directory) so Deck can resolve which project you are working in; pass \
        `project` only to target a different project by name. Before filing a new ticket, \
        consider search_tickets to avoid duplicates. Do not create projects without asking \
        the user first.
        """

    struct Tool {
        let name: String
        let description: String
        let inputSchema: JSONValue
        let handler: ([String: JSONValue]) throws -> JSONValue
    }

    let repository: Repository
    private(set) var tools: [Tool] = []

    public init(repository: Repository) {
        self.repository = repository
        registerTools()
    }

    // MARK: - HTTP-level entry point

    public struct Response {
        public let status: Int
        public let body: Data?
    }

    /// Handles the body of a POST /mcp request.
    public func handlePost(body: Data) -> Response {
        guard let message = try? JSONValue.parse(body) else {
            let error = Self.errorResponse(id: .null, code: -32700, message: "Parse error")
            return Response(status: 400, body: error.serialized())
        }

        if let batch = message.arrayValue {
            let responses = batch.compactMap { handleMessage($0) }
            if responses.isEmpty {
                return Response(status: 202, body: nil)
            }
            return Response(status: 200, body: JSONValue.array(responses).serialized())
        }

        guard let response = handleMessage(message) else {
            return Response(status: 202, body: nil)
        }
        return Response(status: 200, body: response.serialized())
    }

    // MARK: - JSON-RPC dispatch

    func handleMessage(_ message: JSONValue) -> JSONValue? {
        let id = message["id"]
        let isNotification = id == nil || id == .null

        guard let method = message["method"]?.stringValue else {
            if isNotification { return nil }
            return Self.errorResponse(id: id!, code: -32600, message: "Invalid request: missing method")
        }

        if method.hasPrefix("notifications/") {
            return nil
        }

        let params = message["params"]?.objectValue ?? [:]

        let result: JSONValue
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? Self.defaultProtocolVersion
            let version = Self.supportedProtocolVersions.contains(requested) ? requested : Self.defaultProtocolVersion
            result = .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(Self.serverName),
                    "version": .string(Self.serverVersion),
                ]),
                "instructions": .string(Self.instructions),
            ])

        case "ping":
            result = .object([:])

        case "tools/list":
            result = .object([
                "tools": .array(tools.map { tool in
                    .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "inputSchema": tool.inputSchema,
                    ])
                })
            ])

        case "tools/call":
            result = callTool(params: params)

        default:
            if isNotification { return nil }
            return Self.errorResponse(id: id!, code: -32601, message: "Method not found: \(method)")
        }

        if isNotification { return nil }
        return .object(["jsonrpc": .string("2.0"), "id": id!, "result": result])
    }

    private func callTool(params: [String: JSONValue]) -> JSONValue {
        guard let name = params["name"]?.stringValue else {
            return Self.toolError("Missing tool name.")
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return Self.toolError("Unknown tool '\(name)'. Available: \(tools.map(\.name).joined(separator: ", "))")
        }
        let arguments = params["arguments"]?.objectValue ?? [:]
        do {
            let payload = try tool.handler(arguments)
            return .object([
                "content": .array([
                    .object(["type": .string("text"), "text": .string(payload.serializedString())])
                ]),
                "isError": .bool(false),
            ])
        } catch let error as DeckError {
            return Self.toolError(error.errorDescription ?? "\(error)")
        } catch {
            return Self.toolError("Internal error: \(error.localizedDescription)")
        }
    }

    static func toolError(_ message: String) -> JSONValue {
        .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string(message)])
            ]),
            "isError": .bool(true),
        ])
    }

    static func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .int(code), "message": .string(message)]),
        ])
    }
}

// MARK: - Tool definitions

extension MCPHandler {
    private static let cwdDescription = "Absolute path of your session's working directory. Always pass this; Deck matches it against each project's registered folders."
    private static let projectDescription = "Project name. Only needed to override the cwd-based match or when no cwd is available."

    private func registerTools() {
        tools = [
            Tool(
                name: "list_projects",
                description: "List all Deck projects with their registered folder paths, board columns, and ticket counts.",
                inputSchema: Self.schema(properties: [:], required: []),
                handler: { [repository] _ in
                    .array(try repository.projects().map { detail in
                        .object([
                            "name": .string(detail.project.name),
                            "paths": .array(detail.paths.map { .string($0.path) }),
                            "columns": .array(detail.columns.map { .string($0.name) }),
                            "ticket_count": .int(detail.ticketCount),
                        ])
                    })
                }
            ),
            Tool(
                name: "create_project",
                description: "Create a new Deck project. Ask the user before creating one. Registers the given folder path so future cwd-based calls resolve to it. Columns default to Ideas, Backlog, In Progress, Done.",
                inputSchema: Self.schema(
                    properties: [
                        "name": Self.prop("string", "Project name (unique)."),
                        "path": Self.prop("string", "Absolute folder path to register for cwd matching (usually the repo root)."),
                        "columns": Self.arrayProp("Custom column names in board order. Omit for the defaults."),
                    ],
                    required: ["name"]
                ),
                handler: { [repository] args in
                    let name = try Self.requireString(args, "name")
                    let paths = args["path"]?.stringValue.map { [$0] } ?? []
                    let columns = args["columns"]?.arrayValue?.compactMap(\.stringValue)
                    let project = try repository.createProject(name: name, paths: paths, columnNames: columns)
                    return try Self.boardJSON(repository, projectId: project.id!)
                }
            ),
            Tool(
                name: "get_board",
                description: "Get a project's board: every column with its tickets in order. \(Self.cwdDescription)",
                inputSchema: Self.projectScopedSchema(),
                handler: { [repository] args in
                    let project = try self.resolve(args)
                    return try Self.boardJSON(repository, projectId: project.id!)
                }
            ),
            Tool(
                name: "create_ticket",
                description: "Create a ticket. Use this to defer ideas, bugs, or follow-ups that come up while working — they land at the top of the column (defaults to the board's first column). \(Self.cwdDescription)",
                inputSchema: Self.projectScopedSchema(
                    extra: [
                        "title": Self.prop("string", "Short ticket title."),
                        "description": Self.prop("string", "Markdown description with the details/context."),
                        "priority": Self.priorityProp(),
                        "tags": Self.arrayProp("Tags for filtering, e.g. [\"bug\", \"mcp\"]."),
                        "column": Self.prop("string", "Column to create the ticket in. Defaults to the first column."),
                    ],
                    required: ["title"]
                ),
                handler: { [repository] args in
                    let project = try self.resolve(args)
                    let ticket = try repository.createTicket(
                        projectId: project.id!,
                        columnName: args["column"]?.stringValue,
                        title: try Self.requireString(args, "title"),
                        details: args["description"]?.stringValue ?? "",
                        priority: try Self.parsePriority(args["priority"]),
                        tags: args["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
                    )
                    return try Self.ticketJSON(repository, id: ticket.id!)
                }
            ),
            Tool(
                name: "get_ticket",
                description: "Get a ticket's full detail: description, priority, tags, and the complete notes timeline.",
                inputSchema: Self.schema(
                    properties: ["id": Self.prop("integer", "Ticket id.")],
                    required: ["id"]
                ),
                handler: { [repository] args in
                    try Self.ticketJSON(repository, id: try Self.requireId(args))
                }
            ),
            Tool(
                name: "update_ticket",
                description: "Update a ticket's title, description, priority, or tags. Only the fields you pass change; tags replace the existing set.",
                inputSchema: Self.schema(
                    properties: [
                        "id": Self.prop("integer", "Ticket id."),
                        "title": Self.prop("string", "New title."),
                        "description": Self.prop("string", "New markdown description (replaces the old one — use add_note for progress updates instead)."),
                        "priority": Self.priorityProp(),
                        "tags": Self.arrayProp("New full set of tags."),
                    ],
                    required: ["id"]
                ),
                handler: { [repository] args in
                    var priority: TicketPriority? = nil
                    if args["priority"] != nil { priority = try Self.parsePriority(args["priority"]) }
                    let ticket = try repository.updateTicket(
                        id: try Self.requireId(args),
                        title: args["title"]?.stringValue,
                        details: args["description"]?.stringValue,
                        priority: priority,
                        tags: args["tags"]?.arrayValue.map { $0.compactMap(\.stringValue) }
                    )
                    return try Self.ticketJSON(repository, id: ticket.id!)
                }
            ),
            Tool(
                name: "move_ticket",
                description: "Move a ticket to another column on its board, e.g. to 'In Progress' when you start it or 'Done' when finished.",
                inputSchema: Self.schema(
                    properties: [
                        "id": Self.prop("integer", "Ticket id."),
                        "column": Self.prop("string", "Target column name."),
                        "placement": Self.enumProp(["top", "bottom"], "Where in the column to place it. Default: top."),
                    ],
                    required: ["id", "column"]
                ),
                handler: { [repository] args in
                    let placement: TicketPlacement = args["placement"]?.stringValue == "bottom" ? .bottom : .top
                    let ticket = try repository.moveTicket(
                        id: try Self.requireId(args),
                        toColumnNamed: try Self.requireString(args, "column"),
                        placement: placement
                    )
                    return try Self.ticketJSON(repository, id: ticket.id!)
                }
            ),
            Tool(
                name: "add_note",
                description: "Append a timestamped note to a ticket's timeline (markdown). Use for progress updates, findings, decisions, and context worth keeping. Notes are append-only.",
                inputSchema: Self.schema(
                    properties: [
                        "id": Self.prop("integer", "Ticket id."),
                        "body": Self.prop("string", "Markdown note body."),
                        "author": Self.prop("string", "Author label. Defaults to 'agent'."),
                    ],
                    required: ["id", "body"]
                ),
                handler: { [repository] args in
                    let id = try Self.requireId(args)
                    _ = try repository.addNote(
                        ticketId: id,
                        author: args["author"]?.stringValue ?? "agent",
                        body: try Self.requireString(args, "body")
                    )
                    return try Self.ticketJSON(repository, id: id)
                }
            ),
            Tool(
                name: "delete_ticket",
                description: "Move a ticket to the trash (recoverable for 30 days via restore_ticket or the app).",
                inputSchema: Self.schema(
                    properties: ["id": Self.prop("integer", "Ticket id.")],
                    required: ["id"]
                ),
                handler: { [repository] args in
                    let ticket = try repository.softDeleteTicket(id: try Self.requireId(args))
                    return .object([
                        "deleted": .bool(true),
                        "id": .int(ticket.id!),
                        "title": .string(ticket.title),
                        "note": .string("Ticket moved to trash. Restorable for 30 days."),
                    ])
                }
            ),
            Tool(
                name: "restore_ticket",
                description: "Restore a trashed ticket back onto its board.",
                inputSchema: Self.schema(
                    properties: ["id": Self.prop("integer", "Ticket id.")],
                    required: ["id"]
                ),
                handler: { [repository] args in
                    let ticket = try repository.restoreTicket(id: try Self.requireId(args))
                    return try Self.ticketJSON(repository, id: ticket.id!)
                }
            ),
            Tool(
                name: "search_tickets",
                description: "Search tickets by text across titles, descriptions, tags, and notes. Use before creating a ticket to avoid duplicates. Searches all projects unless scoped. \(Self.cwdDescription)",
                inputSchema: Self.schema(
                    properties: [
                        "query": Self.prop("string", "Search text (case-insensitive substring match)."),
                        "project": Self.prop("string", "Limit to this project by name."),
                        "cwd": Self.prop("string", "Limit to the project matching this working directory."),
                        "include_trashed": Self.prop("boolean", "Also search trashed tickets. Default false."),
                    ],
                    required: ["query"]
                ),
                handler: { [repository] args in
                    var projectId: Int64? = nil
                    if args["project"] != nil || args["cwd"] != nil {
                        projectId = try self.resolve(args).id
                    }
                    let hits = try repository.search(
                        query: try Self.requireString(args, "query"),
                        projectId: projectId,
                        includeTrashed: args["include_trashed"]?.boolValue ?? false
                    )
                    return .array(hits.map { hit in
                        .object([
                            "id": .int(hit.ticket.id!),
                            "project": .string(hit.projectName),
                            "column": .string(hit.columnName),
                            "title": .string(hit.ticket.title),
                            "priority": .string(hit.ticket.priority.rawValue),
                            "tags": .array(hit.ticket.tagList.map { .string($0) }),
                            "trashed": .bool(hit.ticket.deletedAt != nil),
                        ])
                    })
                }
            ),
            Tool(
                name: "add_column",
                description: "Add a column to the end of a project's board. \(Self.cwdDescription)",
                inputSchema: Self.projectScopedSchema(
                    extra: ["name": Self.prop("string", "New column name.")],
                    required: ["name"]
                ),
                handler: { [repository] args in
                    let project = try self.resolve(args)
                    _ = try repository.addColumn(projectId: project.id!, name: try Self.requireString(args, "name"))
                    return try Self.boardJSON(repository, projectId: project.id!)
                }
            ),
            Tool(
                name: "rename_column",
                description: "Rename a board column. Tickets stay put. \(Self.cwdDescription)",
                inputSchema: Self.projectScopedSchema(
                    extra: [
                        "from": Self.prop("string", "Current column name."),
                        "to": Self.prop("string", "New column name."),
                    ],
                    required: ["from", "to"]
                ),
                handler: { [repository] args in
                    let project = try self.resolve(args)
                    try repository.renameColumn(
                        projectId: project.id!,
                        from: try Self.requireString(args, "from"),
                        to: try Self.requireString(args, "to")
                    )
                    return try Self.boardJSON(repository, projectId: project.id!)
                }
            ),
            Tool(
                name: "delete_column",
                description: "Delete a board column. If it still holds tickets, pass move_tickets_to naming the column that should receive them. \(Self.cwdDescription)",
                inputSchema: Self.projectScopedSchema(
                    extra: [
                        "name": Self.prop("string", "Column to delete."),
                        "move_tickets_to": Self.prop("string", "Column that receives this column's tickets."),
                    ],
                    required: ["name"]
                ),
                handler: { [repository] args in
                    let project = try self.resolve(args)
                    try repository.deleteColumn(
                        projectId: project.id!,
                        name: try Self.requireString(args, "name"),
                        moveTicketsTo: args["move_tickets_to"]?.stringValue
                    )
                    return try Self.boardJSON(repository, projectId: project.id!)
                }
            ),
            Tool(
                name: "reorder_columns",
                description: "Reorder a board's columns. Pass every column name exactly once, in the desired order. \(Self.cwdDescription)",
                inputSchema: Self.projectScopedSchema(
                    extra: ["order": Self.arrayProp("All column names in the new left-to-right order.")],
                    required: ["order"]
                ),
                handler: { [repository] args in
                    let project = try self.resolve(args)
                    let order = args["order"]?.arrayValue?.compactMap(\.stringValue) ?? []
                    try repository.reorderColumns(projectId: project.id!, orderedNames: order)
                    return try Self.boardJSON(repository, projectId: project.id!)
                }
            ),
        ]
    }

    // MARK: - Argument helpers

    private func resolve(_ args: [String: JSONValue]) throws -> Project {
        try repository.resolveProject(
            name: args["project"]?.stringValue,
            cwd: args["cwd"]?.stringValue
        )
    }

    private static func requireString(_ args: [String: JSONValue], _ key: String) throws -> String {
        guard let value = args[key]?.stringValue, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DeckError.invalidInput("Missing required argument '\(key)'.")
        }
        return value
    }

    private static func requireId(_ args: [String: JSONValue]) throws -> Int64 {
        if let id = args["id"]?.intValue { return id }
        if let string = args["id"]?.stringValue, let id = Int64(string) { return id }
        throw DeckError.invalidInput("Missing required integer argument 'id'.")
    }

    private static func parsePriority(_ value: JSONValue?) throws -> TicketPriority {
        guard let value else { return .none }
        guard let raw = value.stringValue, let priority = TicketPriority(rawValue: raw.lowercased()) else {
            let allowed = TicketPriority.allCases.map(\.rawValue).joined(separator: ", ")
            throw DeckError.invalidInput("Invalid priority. Allowed values: \(allowed).")
        }
        return priority
    }

    // MARK: - Result payloads

    static let dateFormatter = ISO8601DateFormatter()

    static func ticketJSON(_ repository: Repository, id: Int64) throws -> JSONValue {
        let detail = try repository.ticketDetail(id: id)
        var object: [String: JSONValue] = [
            "id": .int(detail.ticket.id!),
            "project": .string(detail.projectName),
            "column": .string(detail.columnName),
            "title": .string(detail.ticket.title),
            "description": .string(detail.ticket.details),
            "priority": .string(detail.ticket.priority.rawValue),
            "tags": .array(detail.ticket.tagList.map { .string($0) }),
            "created_at": .string(dateFormatter.string(from: detail.ticket.createdAt)),
            "updated_at": .string(dateFormatter.string(from: detail.ticket.updatedAt)),
            "notes": .array(detail.notes.map { note in
                .object([
                    "author": .string(note.author),
                    "at": .string(dateFormatter.string(from: note.createdAt)),
                    "body": .string(note.body),
                ])
            }),
        ]
        if detail.ticket.deletedAt != nil {
            object["trashed"] = .bool(true)
        }
        return .object(object)
    }

    static func boardJSON(_ repository: Repository, projectId: Int64) throws -> JSONValue {
        let project = try repository.project(id: projectId)
        let board = try repository.board(projectId: projectId)
        return .object([
            "project": .string(project.name),
            "columns": .array(board.map { columnTickets in
                .object([
                    "name": .string(columnTickets.column.name),
                    "tickets": .array(columnTickets.tickets.map { ticket in
                        .object([
                            "id": .int(ticket.id!),
                            "title": .string(ticket.title),
                            "priority": .string(ticket.priority.rawValue),
                            "tags": .array(ticket.tagList.map { .string($0) }),
                        ])
                    }),
                ])
            }),
        ])
    }

    // MARK: - Schema helpers

    private static func prop(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    private static func arrayProp(_ description: String) -> JSONValue {
        .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(description),
        ])
    }

    private static func enumProp(_ values: [String], _ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map { .string($0) }),
            "description": .string(description),
        ])
    }

    private static func priorityProp() -> JSONValue {
        enumProp(TicketPriority.allCases.map(\.rawValue), "Ticket priority. Default: none.")
    }

    private static func schema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            object["required"] = .array(required.map { .string($0) })
        }
        return .object(object)
    }

    private static func projectScopedSchema(extra: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
        var properties = extra
        properties["cwd"] = prop("string", cwdDescription)
        properties["project"] = prop("string", projectDescription)
        return schema(properties: properties, required: required)
    }
}
