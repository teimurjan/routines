import RoutinesKit
import SwiftUI

/// Semantic names over the generated tokens. Change a value in design/tokens.json, not here.
enum Theme {
    static let sidebar = Tokens.Color.sidebar
    static let canvas = Tokens.Color.canvas
    static let column = Tokens.Color.column
    static let columnBorder = Tokens.Color.columnBorder
    static let card = Tokens.Color.card
    static let cardBorder = Tokens.Color.cardBorder
    static let pill = Tokens.Color.pill
    static let selection = Tokens.Color.selection
    static let text = Tokens.Color.text
    static let muted = Tokens.Color.muted
    static let faint = Tokens.Color.faint
    static let danger = Tokens.Color.danger
    static let success = Tokens.Color.success
    static let warning = Tokens.Color.warning
    static let onAccent = Tokens.Color.onAccent
    static let radius = Tokens.Radius.card
}

extension View {
    /// The horizontal and vertical padding of a control token.
    func padding(_ inset: Tokens.Inset) -> some View {
        padding(.horizontal, inset.x).padding(.vertical, inset.y)
    }

    func shadow(_ style: Tokens.ShadowStyle) -> some View {
        shadow(color: .black.opacity(style.opacity), radius: style.radius, y: style.y)
    }
}

extension Color {
    /// Each value has 8 hex digits with the alpha last, as `Tokens.swift` writes them.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgba: isDark ? dark : light)
        })
    }

    /// A manifest color with 6 hex digits.
    init(hex text: String) {
        let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(nsColor: NSColor(rgba: ((UInt32(digits, radix: 16) ?? 0x6B7280) << 8) | 0xFF))
    }
}

extension NSColor {
    convenience init(rgba: UInt32) {
        let channel = { (shift: UInt32) in CGFloat((rgba >> shift) & 0xFF) / 255 }
        self.init(srgbRed: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }
}

enum AccentColor {
    /// The accent color of the Mac as `#RRGGBB`, for the `--accent` of a plugin UI.
    @MainActor
    static func hex() -> String {
        let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor(rgba: 0x007AFFFF)
        let channel = { (value: CGFloat) in String(format: "%02X", Int((value * 255).rounded())) }
        return "#\(channel(color.redComponent))\(channel(color.greenComponent))\(channel(color.blueComponent))"
    }
}

extension PluginEntry {
    var tint: Color { Color(hex: manifest.color) }
}

/// The emoji of a plugin, or its color dot when the manifest has no emoji.
struct PluginMark: View {
    var plugin: PluginEntry
    var size: CGFloat = 14

    var body: some View {
        if let emoji = plugin.manifest.emoji {
            Text(emoji).font(.system(size: size))
        } else {
            Circle().fill(plugin.tint).frame(width: size * 0.6, height: size * 0.6)
        }
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.day().month(.abbreviated)) }
}
