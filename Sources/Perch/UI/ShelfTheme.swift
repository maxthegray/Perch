import Combine
import SwiftUI

/// The two looks the user can toggle between at runtime (Settings ▸ Appearance).
enum ShelfStyle: String, CaseIterable {
    /// Refined native glass: deeper translucency, hairline border, and accent edge pill.
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

    // Card (no window drop shadow — see ShelfPanel.hasShadow — to avoid a dark outline)
    let cardCornerRadius: CGFloat
    /// Glass is a translucent material; minimal is a flat solid gray (adaptive to
    /// light/dark) with no see-through.
    let cardBackground: AnyShapeStyle
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
                cardBackground: AnyShapeStyle(.ultraThinMaterial),
                cardStrokeColor: .white.opacity(0.12),
                cardStrokeWidth: 0.5,
                rowHeight: 50,
                // Concentric with the card: cardCornerRadius − contentPadding, so the
                // row highlight's corners share the card's curvature instead of looking
                // squarer than the corner they sit inside.
                rowCornerRadius: 12,
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
                cardBackground: AnyShapeStyle(Color(nsColor: minimalCardGray)),
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

    /// Minimal's flat card gray — a shade lighter than `windowBackgroundColor` in both
    /// appearances so the card reads as a surface, not a hole.
    private static let minimalCardGray = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.30, alpha: 1)
            : NSColor(white: 0.95, alpha: 1)
    }
}

/// Holds the active style, persists it, and publishes changes so SwiftUI views and the
/// AppKit edge tab can react live.
@MainActor
final class ThemeStore: ObservableObject {
    private static let key = "Perch.ShelfStyle"
    private static let labelsKey = "Perch.ShowsLabels"
    private static let grabHandleKey = "Perch.ShowsGrabHandle"
    private static let shadowKey = "Perch.ShowsShadow"
    private static let widthScaleKey = "Perch.WidthScale"
    private static let heightFractionKey = "Perch.HeightFraction"

    /// Bounds of the width slider (75%–200% of the design width).
    static let widthScaleRange: ClosedRange<CGFloat> = 0.75...2
    /// Bounds of the height slider: 0 = hug the content (the default), 1 = fill the
    /// screen's usable height.
    static let heightFractionRange: ClosedRange<CGFloat> = 0...1

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

    /// How the user moves the shelf. On, hovering reveals a dedicated grab handle;
    /// off, holding Command while dragging anywhere on the card moves it instead.
    /// The existing boolean key is retained so upgrades preserve the user's choice.
    @Published var showsGrabHandle: Bool {
        didSet {
            guard showsGrabHandle != oldValue else { return }
            UserDefaults.standard.set(showsGrabHandle, forKey: Self.grabHandleKey)
        }
    }

    /// Whether the perch casts a drop shadow. Off by default to keep glass from reading
    /// as a dark outline. Drives `ShelfPanel.hasShadow` (see ShelfController).
    @Published var showsShadow: Bool {
        didSet {
            guard showsShadow != oldValue else { return }
            UserDefaults.standard.set(showsShadow, forKey: Self.shadowKey)
        }
    }

    /// The card's width multiplier, applied by the controller's width math. Driven live
    /// by the Settings window's Width slider; callers keep it within `widthScaleRange` (the
    /// slider is bounded, and the loaded value is clamped in init). Never reassign it
    /// in here — on a @Published property that re-enters didSet and recurses to a crash.
    @Published var widthScale: CGFloat {
        didSet {
            guard widthScale != oldValue else { return }
            UserDefaults.standard.set(Double(widthScale), forKey: Self.widthScaleKey)
        }
    }

    /// The card's minimum height, as a fraction of the screen's usable height. Zero
    /// hugs the content (the original behavior); anything above floors the card taller,
    /// with the extra space acting as a bigger drop target. Same didSet rules as
    /// `widthScale`.
    @Published var heightFraction: CGFloat {
        didSet {
            guard heightFraction != oldValue else { return }
            UserDefaults.standard.set(Double(heightFraction), forKey: Self.heightFractionKey)
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
        showsGrabHandle = UserDefaults.standard.object(forKey: Self.grabHandleKey) as? Bool ?? false
        showsShadow = UserDefaults.standard.object(forKey: Self.shadowKey) as? Bool ?? false
        let clamp: (Double, ClosedRange<CGFloat>) -> CGFloat = {
            min(max(CGFloat($0), $1.lowerBound), $1.upperBound)
        }
        widthScale = (UserDefaults.standard.object(forKey: Self.widthScaleKey) as? Double)
            .map { clamp($0, Self.widthScaleRange) } ?? 1
        heightFraction = (UserDefaults.standard.object(forKey: Self.heightFractionKey) as? Double)
            .map { clamp($0, Self.heightFractionRange) } ?? 0
    }

    func toggle(to style: ShelfStyle) {
        self.style = style
    }
}
