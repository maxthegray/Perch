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

/// The card's size, as one choice instead of two sliders.
///
/// Width and height used to be continuous and were *also* driven by three preset buttons,
/// so the same state had two editors that had to be kept in sync — and a third persisted
/// flag existed purely to remember which preset the numbers had come from. One enum
/// removes all of that; the geometry code still reads a width multiplier and a height
/// fraction, it just no longer has to wonder where they came from.
enum ShelfSizePreset: String, CaseIterable {
    case standard, wide, tall, full

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .wide: return "Wide"
        case .tall: return "Tall"
        case .full: return "Full"
        }
    }

    /// Multiplier on the design width.
    var widthScale: CGFloat {
        switch self {
        case .wide: return 1.5
        case .standard, .tall, .full: return 1
        }
    }

    /// Minimum height as a fraction of the screen's usable height. Zero hugs the content;
    /// anything above floors the card taller, the extra space acting as a drop target.
    var heightFraction: CGFloat {
        switch self {
        case .standard, .wide: return 0
        case .tall: return 0.8
        case .full: return 1
        }
    }

    /// A stacked shelf is always square, so the two height presets have nothing to say
    /// about it and are offered only for the list arrangement.
    var isAvailableWhileStacking: Bool {
        heightFraction == 0
    }

    /// Maps the old width/height pair onto the closest preset, for installs upgrading
    /// from the sliders. The retired Square preset was 150% width with a small height
    /// floor, which lands on `wide`.
    static func nearest(widthScale: CGFloat, heightFraction: CGFloat) -> ShelfSizePreset {
        if heightFraction >= 0.9 { return .full }
        if heightFraction >= 0.4 { return .tall }
        return widthScale >= 1.25 ? .wide : .standard
    }
}

/// Holds the active style, persists it, and publishes changes so SwiftUI views and the
/// AppKit edge tab can react live.
@MainActor
final class ThemeStore: ObservableObject {
    private static let key = PerchSettings.shelfStyle
    private static let labelsKey = PerchSettings.showsLabels
    private static let grabHandleKey = PerchSettings.showsGrabHandle
    private static let shadowKey = PerchSettings.showsShadow
    private static let edgeTabKey = PerchSettings.showsEdgeTab
    private static let sizePresetKey = PerchSettings.sizePreset
    private static let stacksItemsKey = PerchSettings.stacksItems
    // Legacy, read once to migrate an install off the sliders and then left alone.
    private static let widthScaleKey = PerchSettings.widthScale
    private static let heightFractionKey = PerchSettings.heightFraction

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

    /// Whether the accent handle at the shelf's dock is drawn while a drag is in
    /// progress. Off leaves the tab invisible; its catch zone stays live, so dragging to
    /// the edge still reveals the shelf.
    @Published var showsEdgeTab: Bool {
        didSet {
            guard showsEdgeTab != oldValue else { return }
            UserDefaults.standard.set(showsEdgeTab, forKey: Self.edgeTabKey)
        }
    }

    /// The card's size. Stacking forces a square card, so a height preset chosen for the
    /// list arrangement is dropped rather than silently ignored when stacking turns on.
    @Published var sizePreset: ShelfSizePreset {
        didSet {
            guard sizePreset != oldValue else { return }
            UserDefaults.standard.set(sizePreset.rawValue, forKey: Self.sizePresetKey)
        }
    }

    /// Whether multiple entries overlap like a deck instead of making the shelf grow
    /// vertically. A stacked shelf is always square — that is what the arrangement is
    /// for, and it is why the height presets are unavailable alongside it.
    @Published var stacksItems: Bool {
        didSet {
            guard stacksItems != oldValue else { return }
            UserDefaults.standard.set(stacksItems, forKey: Self.stacksItemsKey)
            if stacksItems, !sizePreset.isAvailableWhileStacking {
                sizePreset = .standard
            }
        }
    }

    /// Multiplier on the design width, applied by the controller's width math.
    var widthScale: CGFloat { sizePreset.widthScale }

    /// Minimum height as a fraction of the screen's usable height. Zero hugs the content.
    var heightFraction: CGFloat { sizePreset.heightFraction }

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
        showsEdgeTab = UserDefaults.standard.object(forKey: Self.edgeTabKey) as? Bool ?? true
        stacksItems = UserDefaults.standard.bool(forKey: Self.stacksItemsKey)

        if let raw = UserDefaults.standard.string(forKey: Self.sizePresetKey),
           let stored = ShelfSizePreset(rawValue: raw) {
            sizePreset = stored
        } else {
            // Upgrading from the sliders: land on whichever preset the stored width and
            // height were closest to, and write it so this runs exactly once.
            let loadedWidthScale = (UserDefaults.standard.object(forKey: Self.widthScaleKey) as? Double)
                .map { CGFloat($0) } ?? 1
            let loadedHeightFraction = (UserDefaults.standard.object(forKey: Self.heightFractionKey) as? Double)
                .map { CGFloat($0) } ?? 0
            let migrated = ShelfSizePreset.nearest(
                widthScale: loadedWidthScale,
                heightFraction: loadedHeightFraction
            )
            sizePreset = migrated
            UserDefaults.standard.set(migrated.rawValue, forKey: Self.sizePresetKey)
        }

        // A stacked shelf is square, so a migrated height preset cannot survive next to it.
        if stacksItems, !sizePreset.isAvailableWhileStacking {
            sizePreset = .standard
        }
    }

    func toggle(to style: ShelfStyle) {
        self.style = style
    }
}
