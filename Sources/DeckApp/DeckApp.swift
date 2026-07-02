import AppKit
import DeckCore
import SwiftUI

@main
struct DeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: AppStore

    @AppStorage("themePalette") private var palette: ThemePalette = .graphiteIris
    @AppStorage("themeTintedColumns") private var tintedColumns = true
    @AppStorage("themeAppearance") private var appearance: ThemeAppearance = .system

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

    private var theme: Theme {
        Theme(palette: palette, tintedColumns: tintedColumns)
    }

    var body: some Scene {
        WindowGroup("Deck") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
                .environment(\.deckTheme, theme)
                .tint(theme.accent)
                .accentColor(theme.accent)
                .onAppear { NSApp.appearance = appearance.nsAppearance }
                .onChange(of: appearance) { NSApp.appearance = $1.nsAppearance }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Ticket") { store.newTicketRequested = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(store.selectedProjectId == nil)
            }
        }

        Settings {
            ThemeSettingsView()
                .environment(\.deckTheme, theme)
                .tint(theme.accent)
                .accentColor(theme.accent)
        }
    }
}

struct ThemeSettingsView: View {
    @AppStorage("themePalette") private var palette: ThemePalette = .graphiteIris
    @AppStorage("themeTintedColumns") private var tintedColumns = true
    @AppStorage("themeAppearance") private var appearance: ThemeAppearance = .system

    var body: some View {
        Form {
            Picker("Theme", selection: $palette) {
                ForEach(ThemePalette.allCases) { palette in
                    Text(palette.displayName).tag(palette)
                }
            }
            Toggle("Tinted columns", isOn: $tintedColumns)
            Picker("Appearance", selection: $appearance) {
                ForEach(ThemeAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(width: 340)
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
