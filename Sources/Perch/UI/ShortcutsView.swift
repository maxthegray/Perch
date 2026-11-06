import SwiftUI

/// One line of the cheat sheet: an optional key glyph, the gesture, what it does.
struct GestureShortcut: Equatable {
    var key: String?
    let gesture: String
    let action: String
}

enum GestureShortcuts {
    /// Only what works with the current settings: a gesture that is switched off, or that
    /// a setting has made redundant, is left out rather than explained.
    static func rows(
        showsGrabHandle: Bool,
        copiesByDefault: Bool,
        revealOnHover: Bool,
        shakeToSummon: Bool,
        shelvesOnEdgeTouch: Bool
    ) -> [GestureShortcut] {
        var rows: [GestureShortcut] = []
        if !copiesByDefault {
            rows.append(GestureShortcut(key: "⌥", gesture: "Drag", action: "Drag out a duplicate"))
        }
        rows.append(showsGrabHandle
            ? GestureShortcut(gesture: "Drag handle", action: "Move shelf")
            : GestureShortcut(key: "⌃", gesture: "Drag", action: "Move shelf"))
        rows += [
            GestureShortcut(key: "⌘", gesture: "Click", action: "Add to selection"),
            GestureShortcut(key: "⇧", gesture: "Click", action: "Select range"),
            GestureShortcut(gesture: "Double-click", action: "Quick Look"),
            GestureShortcut(gesture: "Right-click", action: "Menu"),
            GestureShortcut(gesture: "Triple-click", action: "Hide shelf")
        ]
        if !revealOnHover {
            rows.append(GestureShortcut(key: "⌃", gesture: "At edge", action: "Show shelf"))
        }
        if shelvesOnEdgeTouch {
            rows.append(GestureShortcut(gesture: "Hold at edge", action: "Tuck away"))
        }
        if shakeToSummon {
            rows.append(GestureShortcut(gesture: "Shake pointer", action: "Summon shelf"))
        }
        return rows
    }
}

struct ShortcutsView: View {
    @AppStorage(PerchSettings.showsGrabHandle) private var showsGrabHandle = false
    @AppStorage(PerchSettings.vendCopies) private var vendCopies = false
    @AppStorage(PerchSettings.revealOnHover) private var revealOnHover = false
    @AppStorage(PerchSettings.shakeToSummon) private var shakeToSummon = false
    @AppStorage(PerchSettings.shelveOnEdgeTouch) private var shelveOnEdgeTouch = true

    private var rows: [GestureShortcut] {
        GestureShortcuts.rows(
            showsGrabHandle: showsGrabHandle,
            copiesByDefault: vendCopies,
            revealOnHover: revealOnHover,
            shakeToSummon: shakeToSummon,
            shelvesOnEdgeTouch: shelveOnEdgeTouch
        )
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    if let key = row.key {
                        Keycap(glyph: key)
                            .gridColumnAlignment(.trailing)
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                    Text(row.gesture)
                        .padding(.trailing, 10)
                    Text(row.action)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .fixedSize()
        .background(.background)
    }
}

/// A modifier drawn as a small key, its name spelled out beside the symbol for anyone
/// who doesn't read ⌥ as Option. Shared with the on-card tips and the welcome window.
struct Keycap: View {
    let glyph: String
    var size: CGFloat = 11

    static func name(for glyph: String) -> String? {
        switch glyph {
        case "⌥": return "Option"
        case "⌃": return "Control"
        case "⌘": return "Command"
        case "⇧": return "Shift"
        default: return nil
        }
    }

    private var label: String {
        Self.name(for: glyph).map { "\(glyph) \($0)" } ?? glyph
    }

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .medium))
            .padding(.horizontal, label.count > 1 ? 5 : 0)
            .frame(minWidth: size + 7, minHeight: size + 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.tertiary, lineWidth: 0.5)
            )
    }
}
