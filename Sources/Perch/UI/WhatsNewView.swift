import AppKit
import SwiftUI

/// What an update changed, shown once after it installs.
///
/// Deliberately smaller than the welcome window it used to mirror. The welcome earns a
/// full sheet because it is teaching an unknown app; this is a note about a version the
/// user already chose to run, and a hero icon over one line of text made a bug fix look
/// like an announcement. Same voice, a quarter of the room.
struct WhatsNewView: View {
    /// Newest first. More than one entry means the user skipped a release.
    let notes: [ReleaseNote]
    let onDismiss: () -> Void

    /// The rows' natural height, measured so the ScrollView can be given one.
    @State private var contentHeight: CGFloat = 0

    /// The heading names the version only when there is exactly one; catching up across
    /// several releases is "what you missed", not a version announcement.
    private var title: String {
        guard let only = notes.first, notes.count == 1 else {
            return "What's New in \(PerchProductIdentity.displayName)"
        }
        return "\(PerchProductIdentity.displayName) \(only.version)"
    }

    private var subtitle: String? {
        guard notes.count == 1 else { return nil }
        return notes.first?.headline
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            notesList
                .padding(.top, 14)
            Spacer(minLength: 14)
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(width: 320)
        .background(.background)
    }

    /// One line: the app's icon at menu-bar scale beside the version. Centering a large
    /// icon over a short note is what made this read as a product announcement.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Several releases' worth of notes can outgrow the window, so the rows scroll while
    /// the header and the button stay put. One release's worth never will, and the
    /// ScrollView is invisible when its content fits.
    ///
    /// The height is measured rather than left to SwiftUI: this window is sized by its
    /// content (`NSHostingController` in a plain `NSWindow`), and a `ScrollView` asked to
    /// size itself in an unbounded vertical context collapses to nothing — which rendered
    /// the header and the button with an empty gap where every highlight should have been.
    private var notesList: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(notes, id: \.version) { note in
                    VStack(alignment: .leading, spacing: 12) {
                        // Only worth labelling when the user is reading more than one
                        // release at a time; otherwise the title above already said it.
                        if notes.count > 1 {
                            Text(verbatim: "\(PerchProductIdentity.displayName) \(note.version)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        ForEach(note.highlights, id: \.title) { highlight in
                            CompactHighlight(
                                symbol: highlight.symbol,
                                title: highlight.title,
                                detail: highlight.detail
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NotesHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
        .onPreferenceChange(NotesHeightKey.self) { contentHeight = $0 }
        .scrollBounceBehavior(.basedOnSize)
        // Exactly as tall as the notes, capped so that catching up on several releases
        // cannot grow the window past the screen.
        .frame(height: min(max(contentHeight, 1), 240))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 8)
            Button("Continue", action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
        }
    }
}

/// The welcome window's `Lesson` row at note scale. Kept separate rather than shrinking
/// `Lesson` itself, so the first-run window it belongs to is left exactly as it is.
private struct CompactHighlight: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.tint)
                .frame(width: 18, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Reports the notes' natural height so the scroll view can adopt it — see `notesList`.
private struct NotesHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
