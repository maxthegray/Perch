import AppKit
import SwiftUI

/// Who is looking at the welcome window. Both see the same words; a returning user's
/// title just says "(again)", and their controls arrive seeded with what they have.
enum WelcomeMode {
    case firstRun
    /// Reopened from a menu, or shown to an install updating into a release that changed
    /// how Perch presents itself.
    case revisit

    var windowTitle: String { title }

    var title: String {
        switch self {
        case .firstRun: return "Welcome to \(PerchProductIdentity.displayName)"
        case .revisit: return "Welcome to \(PerchProductIdentity.displayName) (again)"
        }
    }

    var subtitle: String { "Mac utility for moving things" }

    var edgeQuestion: String { "Where should it hang out?" }

    var confirmTitle: String { "Show me where it lives" }
}

/// The one thing Perch shows on a new install.
///
/// Perch keeps out of the way, so an ordinary launch produces almost nothing on screen.
/// That is fine on the hundredth launch and disorienting on the first: nothing says that
/// dragging is what summons the shelf, or where Settings live. This window says so.
///
/// It is deliberately a single card rather than a paged tour. There are three things to
/// know and two questions to ask, and a wizard for that much would be heavier than the
/// app it introduces.
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
    /// First run, or a returning user taking the tour again.
    var mode: WelcomeMode = .firstRun
    /// Called when the user is done. The answers are read from `choices`.
    let onFinish: () -> Void
    var onShowShortcuts: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            lessons
                .padding(.top, 18)
            edgeChoice
                .padding(.top, 16)
            revealChoice
                .padding(.top, 14)
            Spacer(minLength: 14)
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
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
            }
            Text(mode.title)
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 2)
            Text(mode.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                // The first-run subtitle is one short line; the revisit's is not, and
                // without this it truncates mid-word instead of wrapping.
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var lessons: some View {
        VStack(alignment: .leading, spacing: 13) {
            Lesson(
                symbol: "cursorarrow.motionlines",
                title: "Drag something",
                detail: "Drag a file and Perch will reveal itself at the edge closest to "
                    + "you. Drop it in and it'll hold onto it. Double-click anything on "
                    + "it to Quick Look it."
            )
            Lesson(
                symbol: "rectangle.righthalf.inset.filled",
                title: "Hide it, bring it back",
                detail: "Once it's holding your stuff it stays out. Push your mouse into "
                    + "that edge to tuck it away, and again to bring it back. "
                    + "Triple-clicking it tucks it away too."
            )
            Lesson(
                symbol: "arrow.down.circle.dotted",
                title: "Your downloads show up on their own",
                detail: "New files from Downloads or your Desktop pop onto the shelf as "
                    + "ghosts. Drag one out to use it, or click it to keep it."
            )
            Lesson(
                symbol: "bird",
                title: "Find it anytime",
                detail: "The bird up in your menu bar or right-clicking the shelf gets you "
                    + "settings + every shortcut."
            )
            Text("No bird? Your menu bar's full. Hold ⌘ and drag some icons out.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 40)
                .padding(.top, -10)
            HStack(spacing: 4) {
                Text("There's a lot more it can do.")
                    .foregroundStyle(.secondary)
                Button("See all the shortcuts", action: onShowShortcuts)
                    .buttonStyle(.link)
            }
            .font(.system(size: 12))
            .padding(.leading, 40)
        }
    }

    /// Which edges the shelf is allowed to live at. Asked here because the answer decides
    /// where the closing reveal happens — the user picks the spot, then watches it light
    /// up — and because an edge the user never reaches for is one Perch appears broken at.
    private var edgeChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.edgeQuestion)
                    .font(.system(size: 13, weight: .semibold))
                Text("Pick as many as you want. You can change it later.")
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

    /// Asked on day one because it is about how someone works, not taste: whether the
    /// shelf may appear unbidden at an edge, or only when reached for.
    private var revealChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When should it pop out?")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                RevealOption(
                    symbol: "hand.draw",
                    title: "When I need it",
                    detail: "Drag something or hold ⌃ Control at the edge",
                    isSelected: !choices.revealOnHover,
                    select: { choices.revealOnHover = false }
                )
                RevealOption(
                    symbol: "cursorarrow.rays",
                    title: "When I touch the edge",
                    detail: "Just put your mouse there",
                    isSelected: choices.revealOnHover,
                    select: { choices.revealOnHover = true }
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeOut(duration: 0.15), value: choices.revealOnHover)
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
        VStack(spacing: 13) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $choices.showsMenuBarIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Perch in the menu bar")
                        Text("Handy while you're still learning the shortcuts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $choices.showsLabels) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show file names")
                        Text("Off just shows the icons, which keeps the shelf skinny")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if loginItemAvailable {
                    Toggle(isOn: $choices.launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Perch when I log in")
                            Text("So it's still there after you restart")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Text("Everything stays on your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(mode.confirmTitle, action: onFinish)
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
        .help(isLocked ? "Perch needs at least one edge" : "")
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

/// One answer to "when should it come out?", drawn like the edge options beside it.
private struct RevealOption: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One "gesture → what happens" line. The symbol carries no meaning the text does not
/// also state, so it stays out of the accessibility tree.
/// One illustrated line: a tinted symbol, a title, and a sentence. Shared with
/// `WhatsNewView` so an update's notes are drawn in the same hand as the welcome's
/// lessons — the two windows are the same window at different moments.
struct Lesson: View {
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
