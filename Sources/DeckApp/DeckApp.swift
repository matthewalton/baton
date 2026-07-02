import AppKit
import DeckCore
import SwiftUI

@main
struct DeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: AppStore

    init() {
        let store: AppStore
        do {
            let database = try AppDatabase.onDisk()
            store = AppStore(repository: Repository(database: database))
        } catch {
            fatalError("Could not open the Deck database: \(error)")
        }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup("Deck") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Ticket") { store.newTicketRequested = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(store.selectedProjectId == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when running as a bare SPM executable (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
