import AppKit
import BatonCore
import SwiftUI

// MARK: - New project

struct NewProjectSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project").font(.title3.weight(.semibold))

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(path ?? "No folder registered yet")
                    .foregroundStyle(path == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose Folder…") {
                    if let chosen = pickFolder() { path = chosen }
                }
            }

            Text("Registering the repo folder lets Claude Code sessions in it file tickets here automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    store.createProject(name: name, path: path)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - New ticket

struct NewTicketSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var priority: TicketPriority = .none
    @State private var tags = ""
    @State private var columnName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Ticket").font(.title3.weight(.semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $details)
                .font(.body)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Description (markdown)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Picker("Column", selection: $columnName) {
                    ForEach(store.board, id: \.column.id) { columnTickets in
                        Text(columnTickets.column.name).tag(String?.some(columnTickets.column.name))
                    }
                }
                .fixedSize()
                Picker("Priority", selection: $priority) {
                    ForEach(TicketPriority.allCases) { priority in
                        Text(priority.rawValue.capitalized).tag(priority)
                    }
                }
                .fixedSize()
                TextField("tags, comma, separated", text: $tags)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    store.createTicket(
                        columnName: columnName,
                        title: title,
                        details: details,
                        priority: priority,
                        tags: tags.split(separator: ",").map(String.init)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            columnName = store.board.first?.column.name
        }
    }
}

// MARK: - Project settings

struct ProjectSettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var newColumnName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let detail = store.selectedProject {
                Text(detail.project.name).font(.title3.weight(.semibold))

                GroupBox("Registered Folders") {
                    VStack(alignment: .leading, spacing: 6) {
                        if detail.paths.isEmpty {
                            Text("No folders registered. Claude Code sessions can't auto-match this project until one is.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(detail.paths, id: \.id) { projectPath in
                            HStack {
                                Text(projectPath.path)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    store.removePath(id: projectPath.id!)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Folder…") {
                            if let chosen = pickFolder(), let id = detail.project.id {
                                store.addPath(projectId: id, path: chosen)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("Columns") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rename, reorder, and delete columns from the ⋯ menu on each column header. Add one here:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("New column name", text: $newColumnName)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                store.addColumn(name: newColumnName)
                                newColumnName = ""
                            }
                            .disabled(newColumnName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            } else {
                Text("No project selected.")
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - Trash

struct TrashSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var trashed: [Ticket] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trash").font(.title3.weight(.semibold))
            Text("Trashed tickets are deleted permanently after 30 days.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if trashed.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
                    .frame(height: 200)
            } else {
                List(trashed, id: \.id) { ticket in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ticket.title)
                            if let deletedAt = ticket.deletedAt {
                                Text("Trashed \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button("Restore") { store.restoreTicket(id: ticket.id!) }
                        Button(role: .destructive) {
                            store.hardDeleteTicket(id: ticket.id!)
                        } label: {
                            Text("Delete Forever")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 280)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .batonDataDidChange)) { _ in
            reload()
        }
    }

    private func reload() {
        guard let projectId = store.selectedProjectId else {
            trashed = []
            return
        }
        trashed = (try? store.repository.trash(projectId: projectId)) ?? []
    }
}

// MARK: - Rename (shared)

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @State var name: String
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}

// MARK: - Helpers

@MainActor
func pickFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Register"
    guard panel.runModal() == .OK else { return nil }
    return panel.url?.path
}
