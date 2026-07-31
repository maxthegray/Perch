import AppKit
import SwiftUI

/// The one thing Perch shows on a new install.
///
/// Perch is an accessory app with no Dock tile and no menu-bar item, so an ordinary
/// launch produces *nothing on screen*. That is fine on the hundredth launch and
/// disorienting on the first: there is no evidence the app started, no way to reach
/// Settings (they live behind a right-click on a shelf the user has not met yet), and no
/// hint that dragging is what summons it. This window is the one place that says so.
///
/// It is deliberately a single card rather than a paged tour. There are exactly three
/// things to know and one question to ask, and a wizard for that much would be heavier
/// than the app it introduces.
struct WelcomeView: View {
    /// Held by the window controller rather than the view, so closing the window with
    /// its red button commits the same answer the "Show Me" button would have — there is
    /// one way to leave this window, not two that disagree.
    @ObservedObject var choices: WelcomeChoices

    let loginItemAvailable: Bool
    /// The edges this Mac can actually offer. The notch is absent on displays without
    /// one, so the picker is built from what the hardware supports rather than from
    /// `ShelfEdge.allCases`.
    let offeredEdges: [ShelfEdge]
    /// Called when the user is done. The answers are read from `choices`.
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            lessons
                .padding(.top, 24)
            edgeChoice
                .padding(.top, 22)
            Spacer(minLength: 18)
            footer
        }
        .padding(.horizontal, 34)
        // The title bar is transparent rather than absent, so it already contributes the
        // clearance the traffic lights need; only a little more is wanted above the icon.
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(width: 460)
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
            }
            Text("Welcome to \(PerchProductIdentity.displayName)")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 2)
            Text("A place to set things down while you work.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var lessons: some View {
        VStack(alignment: .leading, spacing: 18) {
            Lesson(
                symbol: "cursorarrow.motionlines",
                title: "Start dragging",
                detail: "Pick up a file, image, or link and the shelf slides out from "
                    + "the edge of your screen. Drop it there to set it down."
            )
            Lesson(
                symbol: "rectangle.righthalf.inset.filled",
                title: "Come back for it",
                detail: "Hover that same edge and the shelf returns with your things. "
                    + "Drag them out into Finder, a message, anywhere."
            )
            Lesson(
                symbol: "contextualmenu.and.cursorarrow",
                title: "Right-click the shelf",
                detail: "Settings, History, and Quick Look all live in its menu. "
                    + "That is the way back to every preference."
            )
        }
    }

    /// Which edges the shelf is allowed to live at. Asked here because the answer decides
    /// where the closing reveal happens — the user picks the spot, then watches it light
    /// up — and because an edge the user never reaches for is one Perch appears broken at.
    private var edgeChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Where should it wait?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Pick as many edges as you like. You can change this later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(offeredEdges, id: \.self) { edge in
                    EdgeOption(
                        edge: edge,
                        isSelected: choices.edges.contains(edge),
                        // The last edge cannot be turned off: `EdgeSettings` refuses an
                        // empty selection, so offering the click would be a lie.
                        isLocked: choices.edges == [edge],
                        toggle: { toggle(edge) }
                    )
                }
            }
        }
    }

    private func toggle(_ edge: ShelfEdge) {
        if choices.edges.contains(edge) {
            guard choices.edges.count > 1 else { return }
            choices.edges.remove(edge)
        } else {
            choices.edges.insert(edge)
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            if loginItemAvailable {
                Divider()
                Toggle(isOn: $choices.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Perch when I log in")
                        Text("Perch has no Dock or menu bar icon, so it is easy to "
                            + "lose track of after a restart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Text("Everything stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Show Me Where It Lives", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// One edge, drawn as a little screen with the shelf's bar on the side it would occupy.
/// A picture answers "which edge is that?" faster than the words Left and Right do,
/// especially for the notch.
private struct EdgeOption: View {
    let edge: ShelfEdge
    let isSelected: Bool
    /// True when this is the only edge left selected — it stays lit but refuses to turn
    /// off, matching `EdgeSettings`.
    let isLocked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 7) {
                screenGlyph
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(isLocked ? "Perch needs at least one edge." : "")
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A 46×30 "screen" with a rounded bar pinned where the shelf would sit.
    private var screenGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.secondary.opacity(0.55), lineWidth: 1)
            bar
        }
        .frame(width: 46, height: 30)
    }

    private var bar: some View {
        let fill = isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.45))
        return GeometryReader { proxy in
            let size = proxy.size
            switch edge {
            case .left:
                RoundedRectangle(cornerRadius: 1.5).fill(fill)
                    .frame(width: 4, height: size.height * 0.62)
                    .position(x: 5, y: size.height / 2)
            case .right:
                RoundedRectangle(cornerRadius: 1.5).fill(fill)
                    .frame(width: 4, height: size.height * 0.62)
                    .position(x: size.width - 5, y: size.height / 2)
            case .notch:
                RoundedRectangle(cornerRadius: 1.5).fill(fill)
                    .frame(width: size.width * 0.42, height: 4)
                    .position(x: size.width / 2, y: 5)
            }
        }
    }

    private var label: String {
        switch edge {
        case .left: return "Left"
        case .right: return "Right"
        case .notch: return "Top"
        }
    }
}

/// One "gesture → what happens" line. The symbol carries no meaning the text does not
/// also state, so it stays out of the accessibility tree.
private struct Lesson: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
