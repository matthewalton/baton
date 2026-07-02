import DeckCore
import MarkdownUI
import SwiftUI

struct TicketDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let ticketId: Int64

    @State private var detail: TicketDetail?
    @State private var editingDescription = false
    @State private var draftDescription = ""
    @State private var draftTitle = ""
    @State private var draftTags = ""
    @State private var newNote = ""

    var body: some View {
        VStack(spacing: 0) {
            if let detail {
                header(detail)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        descriptionSection(detail)
                        Divider()
                        notesSection(detail)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                footer(detail)
            } else {
                ContentUnavailableView("Ticket not found", systemImage: "questionmark.square")
                    .frame(maxHeight: .infinity)
                Button("Close") { dismiss() }.padding()
            }
        }
        .frame(width: 620, height: 640)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .deckDataDidChange)) { _ in
            reload()
        }
    }

    private func reload() {
        let previous = detail
        detail = try? store.repository.ticketDetail(id: ticketId)
        guard let detail else { return }
        if previous == nil {
            draftTitle = detail.ticket.title
            draftTags = detail.ticket.tagList.joined(separator: ", ")
            draftDescription = detail.ticket.details
        }
    }

    // MARK: - Sections

    private func header(_ detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $draftTitle)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(saveHeaderEdits)

                Text("#\(detail.ticket.id ?? 0)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Picker("", selection: priorityBinding(detail)) {
                    ForEach(TicketPriority.allCases) { priority in
                        Text(priority.rawValue.capitalized).tag(priority)
                    }
                }
                .fixedSize()

                Picker("", selection: columnBinding(detail)) {
                    ForEach(store.board, id: \.column.id) { columnTickets in
                        Text(columnTickets.column.name).tag(columnTickets.column.name)
                    }
                }
                .fixedSize()

                TextField("tags, comma, separated", text: $draftTags)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveHeaderEdits)

                if detail.ticket.deletedAt != nil {
                    Label("In Trash", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
            .font(.callout)

            Text("Created \(detail.ticket.createdAt.formatted(date: .abbreviated, time: .shortened)) · Updated \(detail.ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private func descriptionSection(_ detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description").font(.headline)
                Spacer()
                Button(editingDescription ? "Save" : "Edit") {
                    if editingDescription {
                        store.attempt {
                            _ = try store.repository.updateTicket(id: ticketId, details: draftDescription)
                        }
                    } else {
                        draftDescription = detail.ticket.details
                    }
                    editingDescription.toggle()
                }
                .font(.callout)
            }

            if editingDescription {
                TextEditor(text: $draftDescription)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
            } else if detail.ticket.details.isEmpty {
                Text("No description.")
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Markdown(detail.ticket.details)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
            }
        }
    }

    private func notesSection(_ detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").font(.headline)

            if detail.notes.isEmpty {
                Text("No notes yet.")
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            ForEach(detail.notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(note.author, systemImage: note.author == "me" ? "person.fill" : "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(note.author == "me" ? Color.blue : Color.purple)
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Markdown(note.body)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            HStack(alignment: .bottom) {
                TextField("Add a note…", text: $newNote, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    store.attempt {
                        _ = try store.repository.addNote(ticketId: ticketId, author: "me", body: newNote)
                    }
                    newNote = ""
                }
                .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func footer(_ detail: TicketDetail) -> some View {
        HStack {
            if detail.ticket.deletedAt == nil {
                Button(role: .destructive) {
                    store.trashTicket(id: ticketId)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            } else {
                Button("Restore") { store.restoreTicket(id: ticketId) }
            }
            Spacer()
            Button("Done") {
                saveHeaderEdits()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Bindings & saves

    private func saveHeaderEdits() {
        guard let detail else { return }
        let tags = draftTags.split(separator: ",").map(String.init)
        let titleChanged = draftTitle != detail.ticket.title
        let tagsChanged = Ticket.joinTags(tags) != detail.ticket.tags
        guard titleChanged || tagsChanged else { return }
        store.attempt {
            _ = try store.repository.updateTicket(
                id: ticketId,
                title: titleChanged ? draftTitle : nil,
                tags: tagsChanged ? tags : nil
            )
        }
    }

    private func priorityBinding(_ detail: TicketDetail) -> Binding<TicketPriority> {
        Binding(
            get: { detail.ticket.priority },
            set: { newValue in
                store.attempt { _ = try store.repository.updateTicket(id: ticketId, priority: newValue) }
            }
        )
    }

    private func columnBinding(_ detail: TicketDetail) -> Binding<String> {
        Binding(
            get: { detail.columnName },
            set: { newValue in
                store.attempt { _ = try store.repository.moveTicket(id: ticketId, toColumnNamed: newValue, placement: .top) }
            }
        )
    }
}
