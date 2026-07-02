import DeckCore
import SwiftUI

struct BoardView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.deckTheme) private var theme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(store.board.enumerated()), id: \.element.column.id) { index, columnTickets in
                    ColumnView(columnTickets: columnTickets, columnIndex: index)
                }
            }
            .padding(12)
        }
        .background(theme.boardBackground)
    }
}

struct ColumnView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.deckTheme) private var theme
    let columnTickets: ColumnTickets
    let columnIndex: Int

    @State private var isTargeted = false
    @State private var renaming = false

    private var column: BoardColumn { columnTickets.column }
    private var visibleTickets: [Ticket] { store.visibleTickets(in: columnTickets) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(visibleTickets, id: \.id) { ticket in
                        TicketCardView(ticket: ticket)
                            .dropDestination(for: String.self) { items, _ in
                                guard let payload = items.first else { return false }
                                store.dropTicket(payload: payload, in: column, before: ticket)
                                return true
                            }
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(8)
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.columnFill(at: columnIndex))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.accent.opacity(isTargeted ? 0.06 : 0))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? theme.accent : theme.columnBorder)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            store.dropTicket(payload: payload, in: column, before: nil)
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .sheet(isPresented: $renaming) {
            RenameSheet(title: "Rename Column", name: column.name) { newName in
                store.renameColumn(from: column.name, to: newName)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(column.name)
                .font(.headline)
                .foregroundStyle(theme.columnName(at: columnIndex) ?? Color.primary)
            Text("\(visibleTickets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer()
            Menu {
                Button("Rename…") { renaming = true }
                Button("Move Left") { store.moveColumn(name: column.name, direction: -1) }
                Button("Move Right") { store.moveColumn(name: column.name, direction: 1) }
                Divider()
                if columnTickets.tickets.isEmpty {
                    Button("Delete Column", role: .destructive) {
                        store.deleteColumn(name: column.name, moveTicketsTo: nil)
                    }
                } else {
                    Menu("Delete Column, Move Tickets To") {
                        ForEach(store.board.filter { $0.column.id != column.id }, id: \.column.id) { other in
                            Button(other.column.name) {
                                store.deleteColumn(name: column.name, moveTicketsTo: other.column.name)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }
}

struct TicketCardView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.deckTheme) private var theme
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(ticket.title)
                    .font(.body.weight(.medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text("#\(ticket.id ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if !ticket.details.isEmpty {
                Text(ticket.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if ticket.priority != .none || !ticket.tagList.isEmpty {
                HStack(spacing: 4) {
                    if ticket.priority != .none {
                        PriorityBadge(priority: ticket.priority)
                    }
                    ForEach(ticket.tagList, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardFill)
                .shadow(color: theme.cardShadow, radius: 1, y: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(String(ticket.id ?? 0))
        .onTapGesture {
            store.openTicket = ticket.id.map(TicketSelection.init)
        }
        .contextMenu {
            Menu("Move To") {
                ForEach(store.board.filter { $0.column.id != ticket.columnId }, id: \.column.id) { other in
                    Button(other.column.name) {
                        store.attempt {
                            _ = try store.repository.moveTicket(
                                id: ticket.id!,
                                toColumnNamed: other.column.name,
                                placement: .top
                            )
                        }
                    }
                }
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                store.trashTicket(id: ticket.id!)
            }
        }
    }
}

struct PriorityBadge: View {
    let priority: TicketPriority

    var color: Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .none: return .gray
        }
    }

    var body: some View {
        Text(priority.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}
