import AppKit
import SwiftUI

/// The Settings window's panes. `SettingsWindowController` hosts each one in its own
/// toolbar tab (General / Appearance / Behavior), System Settings-style.
///
/// The behavior flags write straight to `UserDefaults` via `@AppStorage` using the same
/// keys the shelf reads live (`ShelfHostView.*Key`), so changes take effect immediately
/// with no extra plumbing. `ThemeStore` and `EdgeSettings` are the existing observable
/// stores; the shelf reacts to them the same way it did from the old menu.

// MARK: - General

struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            if loginItem.isAvailable {
                Section {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .onAppear { launchAtLogin = loginItem.isEnabled }
                }
            }

            Section {
                LabeledContent("Version", value: appVersion)
                Button("Check for Updates…") {
                    Updater.shared.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Registration can fail (e.g. unbundled builds); revert the toggle to reality.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                launchAtLogin = loginItem.setEnabled(enabled) ? enabled : loginItem.isEnabled
            }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

// MARK: - Appearance

struct AppearanceSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $themeStore.style) {
                    ForEach(ShelfStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show names", isOn: $themeStore.showsLabels)
                Toggle("Shadow", isOn: $themeStore.showsShadow)
            }

            Section("Size") {
                LabeledContent("Width") {
                    Slider(value: widthScaleBinding, in: ThemeStore.widthScaleRange)
                }

                LabeledContent("Height") {
                    Slider(value: $themeStore.heightFraction, in: ThemeStore.heightFractionRange)
                }

                Button("Reset Size") {
                    themeStore.heightFraction = 0
                    themeStore.widthScale = 1
                }
                .disabled(themeStore.heightFraction == 0 && themeStore.widthScale == 1)
            }
        }
        .formStyle(.grouped)
    }

    /// Detent at the design width: close enough to 100% snaps the thumb and the value.
    private var widthScaleBinding: Binding<CGFloat> {
        Binding(
            get: { themeStore.widthScale },
            set: { themeStore.widthScale = abs($0 - 1) < 0.04 ? 1 : $0 }
        )
    }
}

// MARK: - Behavior

struct BehaviorSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var edgeSettings: EdgeSettings

    @AppStorage(ShelfHostView.shakeToSummonKey) private var shakeToSummon = true
    @AppStorage(ShelfHostView.revealOnDragStartKey) private var revealOnDragStart = true
    @AppStorage(ShelfHostView.keepEmptyShelfKey) private var keepEmptyShelf = true
    @AppStorage(ShelfHostView.vendCopiesKey) private var vendCopies = false
    @AppStorage(RecentArrivals.enabledKey) private var offerRecentArrivals = true

    var body: some View {
        Form {
            Section {
                behaviorRow(
                    demo: .shakeToSummon,
                    title: "Shake to summon",
                    caption: "Shake the cursor to reveal the shelf.",
                    isOn: $shakeToSummon
                )
                behaviorRow(
                    demo: .revealOnDrag,
                    title: "Auto-show while dragging",
                    caption: "The shelf slides out when you start dragging a file.",
                    isOn: $revealOnDragStart
                )
                behaviorRow(
                    demo: .keepEmpty,
                    flag: keepEmptyShelf,
                    title: "Keep open when empty",
                    caption: "The shelf stays out after its last item leaves.",
                    isOn: $keepEmptyShelf
                )
                behaviorRow(
                    demo: .moveShelf,
                    title: "Dragging enabled",
                    caption: "Hover the shelf and grab the handle to move it anywhere on the screen.",
                    isOn: $themeStore.showsGrabHandle
                )
            }

            Section {
                HStack(alignment: .center, spacing: 12) {
                    BehaviorDemo(kind: .dragOut, flag: vendCopies)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drag out")
                        Text(vendCopies
                            ? "Dragging an item out leaves it on the shelf."
                            : "Dragging an item out removes it from the shelf.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Picker("Drag out", selection: $vendCopies) {
                        Text("Move").tag(false)
                        Text("Copy").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.vertical, 2)
            }

            Section {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offer recent downloads")
                        Text("Files that just landed in Downloads or on the Desktop appear as dimmed rows — click one to bring it aboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Offer recent downloads", isOn: $offerRecentArrivals)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
            }

            Section("Docking") {
                dockEdgeToggles
            }
        }
        .formStyle(.grouped)
    }

    private func behaviorRow(
        demo: BehaviorDemo.Kind,
        flag: Bool = true,
        title: String,
        caption: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            BehaviorDemo(kind: demo, flag: flag)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    /// One toggle per dockable edge. The last enabled edge is disabled rather than
    /// silently refused (EdgeSettings won't drop below one), so the constraint is visible.
    @ViewBuilder
    private var dockEdgeToggles: some View {
        let entries: [(String, ShelfEdge)] = [
            ("Left edge", .left), ("Right edge", .right), ("Top (Notch)", .notch)
        ]
        ForEach(entries, id: \.1) { title, edge in
            Toggle(title, isOn: Binding(
                get: { edgeSettings.isEnabled(edge) },
                set: { _ in edgeSettings.toggle(edge) }
            ))
            .disabled(edgeSettings.isEnabled(edge) && edgeSettings.enabledEdges.count == 1)
        }
    }
}

// MARK: - Behavior demos

/// A looping miniature scene that acts out one behavior setting inside a tiny "screen".
/// Driven by wall-clock time (`TimelineView`), so every element's position is a pure
/// function of the loop time and no animation state is kept. `flag` lets the state-aware
/// demos (keep-open, move/copy) act out whichever variant is currently selected.
private struct BehaviorDemo: View {
    enum Kind {
        case shakeToSummon, revealOnDrag, keepEmpty, moveShelf, dragOut
    }

    let kind: Kind
    var flag = true

    private static let width: CGFloat = 112
    private static let height: CGFloat = 64
    /// The shelf's center x when docked at the right edge, and when slid offscreen.
    private static let shelfShownX: CGFloat = 92
    private static let shelfHiddenX: CGFloat = 130

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration)
            scene(at: t)
                // Brief crossfade at the loop boundary hides every scene's reset jump.
                .opacity(min(ramp(t, 0, 0.25), 1 - ramp(t, duration - 0.25, duration)))
        }
        .frame(width: Self.width, height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    private var duration: Double {
        switch kind {
        case .shakeToSummon, .moveShelf: return 4.6
        case .revealOnDrag, .keepEmpty, .dragOut: return 5.2
        }
    }

    @ViewBuilder
    private func scene(at t: Double) -> some View {
        switch kind {
        case .shakeToSummon: shakeScene(t)
        case .revealOnDrag: revealScene(t)
        case .keepEmpty: keepEmptyScene(t)
        case .moveShelf: moveShelfScene(t)
        case .dragOut: dragOutScene(t)
        }
    }

    /// Cursor wiggles in place, the shelf slides in, lingers, and slides back out.
    private func shakeScene(_ t: Double) -> some View {
        let envelope = ramp(t, 0.7, 0.9) - ramp(t, 1.5, 1.7)
        let wiggle = sin((t - 0.7) * 24) * 7 * envelope
        let shelfIn = ramp(t, 1.6, 2.0) - ramp(t, 3.7, 4.1)
        return ZStack {
            shelf(rows: [1, 1, 1], x: shelfX(shelfIn))
            cursor(x: 46 + wiggle, y: 36)
        }
    }

    /// A file gets picked up on the desktop; the shelf peeks out to catch it.
    private func revealScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.2, 0.8)
        let drag = ramp(t, 1.0, 2.6)
        let dropped = ramp(t, 2.6, 2.9)
        let shelfIn = ramp(t, 1.2, 1.6) - ramp(t, 4.2, 4.6)
        let docX = lerp(20, 78, drag)
        let docY = lerp(46, 32, drag)
        return ZStack {
            shelf(rows: [1, 1, dropped], x: shelfX(shelfIn))
            file(x: docX, y: docY, opacity: 1 - dropped)
            cursor(x: lerp(58, docX + 4, approach), y: lerp(18, docY + 4, approach))
        }
    }

    /// The only item leaves the shelf. With the flag on the empty shelf stays put;
    /// off, it slides away once the item is gone.
    private func keepEmptyScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.5, 1.1)
        let pull = ramp(t, 1.4, 2.7)
        let pickup = ramp(t, 1.4, 1.6)
        let settle = ramp(t, 3.1, 3.5)
        let shelfIn = flag ? 1 : 1 - ramp(t, 3.7, 4.2)
        let itemX = lerp(Self.shelfShownX, 32, pull)
        let itemY = lerp(30, 44, pull)
        return ZStack {
            shelf(rows: [1 - pickup], x: shelfX(shelfIn))
            file(x: itemX, y: itemY, opacity: pickup * (1 - settle))
            cursor(x: lerp(48, itemX + 4, approach), y: lerp(52, itemY + 4, approach))
        }
    }

    /// Cursor grabs the handle and pulls the whole shelf off its edge, parking it
    /// free-floating in the middle of the screen.
    private func moveShelfScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.3, 0.9)
        let drag = ramp(t, 1.1, 2.3) - ramp(t, 3.2, 4.0)
        let shelfX = lerp(Self.shelfShownX, 46, drag)
        let shelfY = lerp(34, 30, drag)
        return ZStack {
            shelf(rows: [1, 1], x: shelfX, y: shelfY, grabber: true)
            cursor(
                x: lerp(40, shelfX, approach),
                y: lerp(18, shelfY - 15, approach)
            )
        }
    }

    /// An item is dragged off the shelf. Copy leaves the original row behind;
    /// Move takes it along.
    private func dragOutScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.3, 0.9)
        let pull = ramp(t, 1.1, 2.5)
        let pickup = ramp(t, 1.1, 1.3)
        let settle = ramp(t, 3.8, 4.3)
        let topRow = flag ? 1 : 1 - pickup
        let itemX = lerp(Self.shelfShownX, 28, pull)
        let itemY = lerp(26, 44, pull)
        return ZStack {
            shelf(rows: [topRow, 1], x: shelfX(1))
            file(x: itemX, y: itemY, opacity: pickup * (1 - settle))
            cursor(x: lerp(44, itemX + 4, approach), y: lerp(52, itemY + 4, approach))
        }
    }

    // MARK: Scene elements

    private func shelfX(_ shownFraction: Double) -> CGFloat {
        lerp(Self.shelfHiddenX, Self.shelfShownX, shownFraction)
    }

    /// The miniature perch: a rounded card with capsule "rows" whose opacities the
    /// scenes animate independently.
    private func shelf(
        rows: [Double], x: CGFloat, y: CGFloat = 32, grabber: Bool = false
    ) -> some View {
        VStack(spacing: 3.5) {
            if grabber {
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 10, height: 2)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, opacity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 15, height: 6)
                    .opacity(opacity)
            }
        }
        .frame(width: 27, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .position(x: x, y: y)
    }

    private func cursor(x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.primary)
            .position(x: x, y: y)
    }

    private func file(x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor.opacity(0.75))
            .opacity(opacity)
            .position(x: x, y: y)
    }

    /// Smoothstep from 0 to 1 as `t` crosses `a`…`b`.
    private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard t > a else { return 0 }
        guard t < b else { return 1 }
        let x = (t - a) / (b - a)
        return x * x * (3 - 2 * x)
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: Double) -> CGFloat {
        from + (to - from) * CGFloat(fraction)
    }
}
