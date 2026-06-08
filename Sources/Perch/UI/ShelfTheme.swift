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

    // Rows. `rowHeight`, `rowSpacing`, and `contentPadding` drive both the SwiftUI
    // layout and the AppKit drag/hover/delete hit-testing (ShelfHostView), so they must
    // stay the single source of truth for row geometry.
    let rowHeight: CGFloat
    let rowCornerRadius: CGFloat
    let rowFill: Color
    let rowHoverFill: Color
    let contentPadding: CGFloat
    let rowSpacing: CGFloat
    let showsDeleteButton: Bool

    // Row anatomy
    let iconSize: CGFloat
    let iconCornerRadius: CGFloat
    let iconShadow: Bool
    let titleSize: CGFloat
    let titleWeight: Font.Weight
    let showsSubtitle: Bool
    let usesRowSeparators: Bool
    let separatorColor: Color

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
                rowHeight: 50,
                rowCornerRadius: 9,
                rowFill: Color.primary.opacity(0.05),
                rowHoverFill: Color.primary.opacity(0.11),
                contentPadding: 6,
                rowSpacing: 4,
                showsDeleteButton: true,
                iconSize: 34,
                iconCornerRadius: 7,
                iconShadow: true,
                titleSize: 13,
                titleWeight: .medium,
                showsSubtitle: true,
                usesRowSeparators: false,
                separatorColor: .clear,
                tabAccent: .controlAccentColor,
                tabUsesGlow: true,
                tabVisibleWidth: 9,
                tabCornerRadius: 9
            )
        case .minimal:
            return ShelfTheme(
                style: .minimal,
                cardCornerRadius: 10,
                cardMaterial: .thinMaterial,
                cardStrokeColor: .white.opacity(0.05),
                cardStrokeWidth: 0.5,
                rowHeight: 34,
                rowCornerRadius: 5,
                rowFill: .clear,
                rowHoverFill: Color.primary.opacity(0.07),
                contentPadding: 5,
                rowSpacing: 0,
                showsDeleteButton: false,
                iconSize: 20,
                iconCornerRadius: 4,
                iconShadow: false,
                titleSize: 12,
                titleWeight: .regular,
                showsSubtitle: false,
                usesRowSeparators: true,
                separatorColor: .primary.opacity(0.08),
                tabAccent: NSColor.tertiaryLabelColor,
                tabUsesGlow: false,
                tabVisibleWidth: 4,
                tabCornerRadius: 2
            )
        }
    }
}

/// Holds the active style, persists it, and publishes changes so SwiftUI views and the
/// AppKit edge tab can react live.
@MainActor
final class ThemeStore: ObservableObject {
    private static let key = "Perch.ShelfStyle"
    private static let labelsKey = "Perch.ShowsLabels"

    @Published var style: ShelfStyle {
        didSet {
            guard style != oldValue else { return }
            UserDefaults.standard.set(style.rawValue, forKey: Self.key)
        }
    }

    /// Whether rows show the item's name/subtitle alongside the icon. When off, the
    /// shelf collapses to a compact icons-only strip.
    @Published var showsLabels: Bool {
        didSet {
            guard showsLabels != oldValue else { return }
            UserDefaults.standard.set(showsLabels, forKey: Self.labelsKey)
        }
    }

    var theme: ShelfTheme { ShelfTheme.resolve(style) }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        style = raw.flatMap(ShelfStyle.init(rawValue:)) ?? .glass
        if UserDefaults.standard.object(forKey: Self.labelsKey) != nil {
            showsLabels = UserDefaults.standard.bool(forKey: Self.labelsKey)
        } else {
            showsLabels = true
        }
    }

    func toggle(to style: ShelfStyle) {
        self.style = style
    }
}
