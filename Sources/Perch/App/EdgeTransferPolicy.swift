/// Gates the opt-in gesture that moves a populated edge shelf to another enabled wall.
enum EdgeTransferPolicy {
    static func canArm(
        enabled: Bool,
        panelVisible: Bool,
        panelFullyRevealed: Bool,
        usesEdgeDock: Bool,
        hasStoredItems: Bool,
        dragInFlight: Bool,
        shelfDragInFlight: Bool,
        arrivalPreviewActive: Bool,
        contextMenuOpen: Bool
    ) -> Bool {
        enabled
            && panelVisible
            && panelFullyRevealed
            && usesEdgeDock
            && hasStoredItems
            && !dragInFlight
            && !shelfDragInFlight
            && !arrivalPreviewActive
            && !contextMenuOpen
    }
}
