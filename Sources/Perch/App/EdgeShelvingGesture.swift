struct EdgeShelvingGesture {
    private(set) var requiresWallExit = false

    mutating func updateContact(isTouchingWall: Bool) {
        if !isTouchingWall {
            requiresWallExit = false
        }
    }

    mutating func consumeContact() {
        requiresWallExit = true
    }
}
