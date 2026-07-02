import AppKit
import SwiftUI

enum ThemePalette: String, CaseIterable, Identifiable {
    case graphiteIris
    case paperPine
    case harbor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphiteIris: return "Graphite & Iris"
        case .paperPine: return "Paper & Pine"
        case .harbor: return "Harbor"
        }
    }
}

enum ThemeAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Semantic colors for the board surfaces. Text keeps the system primary/secondary
/// styles so it always adapts; priority badge colors are fixed across themes.
struct Theme {
    let palette: ThemePalette
    let tintedColumns: Bool

    var accent: Color {
        switch palette {
        case .graphiteIris: return dynamic(light: "#5E6AD2", dark: "#7B87E8")
        case .paperPine: return dynamic(light: "#3E7C5B", dark: "#5FA37E")
        case .harbor: return dynamic(light: "#0E8C8C", dark: "#3ECFB2")
        }
    }

    var boardBackground: Color {
        switch palette {
        case .graphiteIris: return dynamic(light: "#F4F4F6", dark: "#17171C")
        case .paperPine: return dynamic(light: "#F5F2EA", dark: "#201E1A")
        case .harbor: return dynamic(light: "#F1F5F6", dark: "#0F1518")
        }
    }

    var cardFill: Color {
        switch palette {
        case .graphiteIris: return dynamic(light: "#FFFFFF", dark: "#27272F")
        case .paperPine: return dynamic(light: "#FFFDF7", dark: "#322F28")
        case .harbor: return dynamic(light: "#FFFFFF", dark: "#1D272C")
        }
    }

    var columnBorder: Color {
        dynamic(light: "#000000", dark: "#FFFFFF", lightAlpha: 0.09, darkAlpha: 0.08)
    }

    var cardShadow: Color {
        dynamic(light: "#000000", dark: "#000000", lightAlpha: 0.10, darkAlpha: 0.35)
    }

    /// Column background; cycles through soft hue tints when tinted columns are on.
    func columnFill(at index: Int) -> Color {
        guard tintedColumns else { return plainColumnFill }
        let tint = Theme.columnTints[index % Theme.columnTints.count]
        return dynamic(light: tint.light, dark: tint.dark)
    }

    /// Header text color for a tinted column; nil means use the default label color.
    func columnName(at index: Int) -> Color? {
        guard tintedColumns else { return nil }
        let tint = Theme.columnTints[index % Theme.columnTints.count]
        return dynamic(light: tint.nameLight, dark: tint.nameDark)
    }

    private var plainColumnFill: Color {
        switch palette {
        case .graphiteIris: return dynamic(light: "#ECECF0", dark: "#1E1E25")
        case .paperPine: return dynamic(light: "#ECE7DB", dark: "#282520")
        case .harbor: return dynamic(light: "#E6EDEF", dark: "#151D21")
        }
    }

    private static let columnTints: [(light: String, dark: String, nameLight: String, nameDark: String)] = [
        ("#E9F0FA", "#1D2430", "#3A62B0", "#8FB0F0"),  // blue
        ("#FAF2E2", "#2B2519", "#9A6B10", "#E8B460"),  // amber
        ("#E7F3EA", "#1C291F", "#2E7D4A", "#7CCB96"),  // green
        ("#F0EAF8", "#262031", "#6B4FA8", "#B49BE8"),  // violet
        ("#F9EAF0", "#2E1F27", "#A8467A", "#E88FB8"),  // rose
        ("#E6F3F5", "#1A2A2E", "#17707E", "#6EC6D4"),  // cyan
    ]

    /// A color that resolves per the window's effective appearance, so the
    /// app-level Light/Dark override applies without any view-level plumbing.
    private func dynamic(light: String, dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(hex: dark, alpha: darkAlpha)
            }
            return NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private struct BatonThemeKey: EnvironmentKey {
    static let defaultValue = Theme(palette: .graphiteIris, tintedColumns: true)
}

extension EnvironmentValues {
    var batonTheme: Theme {
        get { self[BatonThemeKey.self] }
        set { self[BatonThemeKey.self] = newValue }
    }
}
