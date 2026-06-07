import Combine
import SwiftUI

/// The two looks the user can toggle between at runtime (right-click ▸ Appearance).
enum ShelfStyle: String, CaseIterable {
    /// Refined native glass: deeper translucency, hairline border, soft shadow, an
    /// accent edge pill.
    case glass
    /// Ultra-minimal: flatter, monochrome, tighter, almost-invisible chrome.
    case minimal

    var displayName: String {
        switch self {
        case .glass: return "Glass"
        case .minimal: return "Minimal"
        }
    }
}

/// Resolved visual tokens for a style. Read by both SwiftUI (card + rows) and AppKit
/// (the edge tab) so every surface stays in sync with the active look.
struct ShelfTheme {
    let style: ShelfStyle

    // Card (the window itself casts the drop shadow — see ShelfPanel.hasShadow)
    let cardCornerRadius: CGFloat
    let cardMaterial: Material
    let cardStrokeColor: Color
    let cardStrokeWidth: CGFloat

    // Rows (note: the *pitch* stays 48pt regardless of style — ShelfHostView.item(at:)
    // depends on it for drag hit-testing — so only the visuals vary here).
    let rowCornerRadius: CGFloat
    let rowFill: Color
    let rowHoverFill: Color
    let contentPadding: CGFloat
    let rowSpacing: CGFloat
    let showsDeleteButton: Bool

    // Edge tab (AppKit)
    let tabAccent: NSColor
    let tabUsesGlow: Bool
    let tabVisibleWidth: CGFloat
    let tabCornerRadius: CGFloat

    static func resolve(_ style: ShelfStyle) -> ShelfTheme {
        switch style {
        case .glass:
            return ShelfTheme(
                style: .glass,
                cardCornerRadius: 18,
                cardMaterial: .ultraThinMaterial,
                cardStrokeColor: .white.opacity(0.12),
                cardStrokeWidth: 0.5,
                rowCornerRadius: 9,
                rowFill: Color.primary.opacity(0.05),
                rowHoverFill: Color.primary.opacity(0.11),
                contentPadding: 6,
                rowSpacing: 4,
                showsDeleteButton: true,
                tabAccent: .controlAccentColor,
                tabUsesGlow: true,
                tabVisibleWidth: 9,
                tabCornerRadius: 9
            )
        case .minimal:
            return ShelfTheme(
                style: .minimal,
                cardCornerRadius: 12,
                cardMaterial: .thinMaterial,
                cardStrokeColor: .white.opacity(0.04),
                cardStrokeWidth: 0.5,
                rowCornerRadius: 6,
                rowFill: .clear,
                rowHoverFill: Color.primary.opacity(0.06),
                contentPadding: 6,
                rowSpacing: 2,
                showsDeleteButton: false,
                tabAccent: NSColor.secondaryLabelColor,
                tabUsesGlow: false,
                tabVisibleWidth: 5,
                tabCornerRadius: 2.5
            )
        }
    }
}

/// Holds the active style, persists it, and publishes changes so SwiftUI views and the
/// AppKit edge tab can react live.
@MainActor
final class ThemeStore: ObservableObject {
    private static let key = "Perch.ShelfStyle"

    @Published var style: ShelfStyle {
        didSet {
            guard style != oldValue else { return }
            UserDefaults.standard.set(style.rawValue, forKey: Self.key)
        }
    }

    var theme: ShelfTheme { ShelfTheme.resolve(style) }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        style = raw.flatMap(ShelfStyle.init(rawValue:)) ?? .glass
    }

    func toggle(to style: ShelfStyle) {
        self.style = style
    }
}
