import AppKit
import SwiftUI

/// What an update changed, shown once after it installs.
///
/// The welcome window's counterpart, and deliberately its twin: same width, same header
/// shape, same illustrated rows. An update should feel like the app it updated, and a
/// user who saw the welcome a month ago should recognize this immediately as the same
/// voice rather than a marketing interruption.
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
                .padding(.top, 24)
            Spacer(minLength: 18)
            footer
        }
        .padding(.horizontal, 34)
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
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 2)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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
            VStack(alignment: .leading, spacing: 20) {
                ForEach(notes, id: \.version) { note in
                    VStack(alignment: .leading, spacing: 18) {
                        // Only worth labelling when the user is reading more than one
                        // release at a time; otherwise the title above already said it.
                        if notes.count > 1 {
                            Text("\(PerchProductIdentity.displayName) \(note.version)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        ForEach(note.highlights, id: \.title) { highlight in
                            Lesson(
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
        .frame(height: min(max(contentHeight, 1), 320))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 8)
            Button("Continue", action: onDismiss)
                .keyboardShortcut(.defaultAction)
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
