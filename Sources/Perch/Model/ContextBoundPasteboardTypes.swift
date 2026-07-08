import AppKit

extension NSPasteboard.PasteboardType {
    /// Flavors that only make sense inside the source app's own drag session, so they
    /// must not be stored or re-vended: replayed from the shelf they hand the
    /// destination a stale handle it can't resolve. Messages' attachment pipeline, for
    /// one, prefers `com.apple.finder.node` over the file promise, fails to load it,
    /// and silently drops the whole attachment. `dyn.*` types wrap legacy carbon-era
    /// flavors that are equally session-bound; every real payload also travels as a
    /// proper UTI flavor.
    var isContextBoundSourceType: Bool {
        rawValue == "com.apple.finder.node" || rawValue.hasPrefix("dyn.")
    }
}
