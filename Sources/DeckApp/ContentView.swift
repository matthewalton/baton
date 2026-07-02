import DeckCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    @State private var showNewProject = false
    @State private var showTrash = false
    @State private var showProjectSettings = false
    @State private var renamingProject: ProjectDetail?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search tickets and notes")
        .sheet(isPresented: $showNewProject) { NewProjectSheet() }
        .sheet(isPresented: $showTrash) { TrashSheet() }
        .sheet(isPresented: $showProjectSettings) { ProjectSettingsSheet() }
        .sheet(item: $store.openTicket) { selection in
            TicketDetailView(ticketId: selection.id)
        }
        .sheet(isPresented: $store.newTicketRequested) { NewTicketSheet() }
        .sheet(item: $renamingProject) { detail in
            RenameSheet(title: "Rename Project", name: detail.project.name) { newName in
                if let id = detail.project.id {
                    store.renameProject(id: id, to: newName)
                }
            }
        }
        .alert("Deck", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedProjectId) {
                Section("Projects") {
                    ForEach(store.projects, id: \.project.id) { detail in
                        Label(detail.project.name, systemImage: "square.stack")
                            .badge(detail.ticketCount)
                            .tag(detail.project.id!)
                            .contextMenu {
                                Button("Rename…") { renamingProject = detail }
                                Button("Settings…") {
                                    store.selectedProjectId = detail.project.id
                                    showProjectSettings = true
                                }
                                Divider()
                                Button("Delete Project…", role: .destructive) {
                                    confirmDeleteProject(detail)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            serverFooter
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    showNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)
                Spacer()
            }
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    private var serverFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let serverError = store.serverError {
                Label(serverError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Label("MCP: \(store.mcpEndpoint)", systemImage: "bolt.horizontal.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detail: some View {
        if let project = store.selectedProject {
            BoardView()
                .navigationTitle(project.project.name)
                .toolbar { boardToolbar }
        } else {
            ContentUnavailableView(
                "No Projects",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Create a project to get a board, or let Claude Code create one via MCP.")
            )
        }
    }

    @ToolbarContentBuilder
    private var boardToolbar: some ToolbarContent {
        ToolbarItemGroup {
            filterMenu

            Button {
                showTrash = true
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .badge(store.selectedProject?.trashCount ?? 0)
            .help("Trashed tickets (kept for 30 days)")

            Button {
                showProjectSettings = true
            } label: {
                Label("Project Settings", systemImage: "gearshape")
            }
            .help("Paths, columns, and renames")

            Button {
                store.newTicketRequested = true
            } label: {
                Label("New Ticket", systemImage: "plus")
            }
            .help("New ticket (⇧⌘N)")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Priority", selection: $store.priorityFilter) {
                Text("Any Priority").tag(TicketPriority?.none)
                ForEach(TicketPriority.allCases) { priority in
                    Text(priority.rawValue.capitalized).tag(TicketPriority?.some(priority))
                }
            }
            Picker("Tag", selection: $store.tagFilter) {
                Text("Any Tag").tag(String?.none)
                ForEach(store.allTags, id: \.self) { tag in
                    Text(tag).tag(String?.some(tag))
                }
            }
            if store.filtersActive {
                Divider()
                Button("Clear Filters") {
                    store.priorityFilter = nil
                    store.tagFilter = nil
                }
            }
        } label: {
            Label("Filter", systemImage: store.filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
    }

    private func confirmDeleteProject(_ detail: ProjectDetail) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(detail.project.name)”?"
        alert.informativeText = "This permanently deletes the project, its \(detail.ticketCount) ticket(s), and its trash. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, let id = detail.project.id {
            store.deleteProject(id: id)
        }
    }
}
