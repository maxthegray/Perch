/// One shared decision for every automatic shelf-hide path. In particular, any active
/// system drag owns a visibility hold, regardless of whether that drag originally
/// revealed the panel.
enum ShelfRetractionPolicy {
    static func shouldRetractEmptyShelf(
        dragActive: Bool,
        shelfDragActive: Bool,
        isFreeFloating: Bool,
        isEmpty: Bool,
        pointerInKeepAliveRegion: Bool,
        contextMenuOpen: Bool
    ) -> Bool {
        !dragActive
            && !shelfDragActive
            && !isFreeFloating
            && isEmpty
            && !pointerInKeepAliveRegion
            && !contextMenuOpen
    }
}
