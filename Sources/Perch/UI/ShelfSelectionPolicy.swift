struct ShelfSelectionPolicy<ItemID: Hashable> {
    enum Modifier {
        case plain
        case command
        case shift
    }

    private(set) var selectedItemIDs: Set<ItemID> = []
    private(set) var anchorItemID: ItemID?

    mutating func click(
        _ itemID: ItemID,
        modifier: Modifier,
        orderedItemIDs: [ItemID]
    ) {
        switch modifier {
        case .plain:
            selectedItemIDs = [itemID]
            anchorItemID = itemID

        case .command:
            if selectedItemIDs.contains(itemID) {
                selectedItemIDs.remove(itemID)
            } else {
                selectedItemIDs.insert(itemID)
            }
            anchorItemID = itemID

        case .shift:
            guard let anchorItemID,
                  let anchorIndex = orderedItemIDs.firstIndex(of: anchorItemID),
                  let clickedIndex = orderedItemIDs.firstIndex(of: itemID)
            else {
                selectedItemIDs = [itemID]
                return
            }
            let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
            selectedItemIDs = Set(orderedItemIDs[range])
        }
    }

    mutating func contextClick(_ itemID: ItemID) {
        guard !selectedItemIDs.contains(itemID) else { return }
        selectedItemIDs = [itemID]
        anchorItemID = itemID
    }

    mutating func replaceSelection(_ itemIDs: Set<ItemID>, anchorItemID: ItemID? = nil) {
        selectedItemIDs = itemIDs
        self.anchorItemID = anchorItemID
    }

    mutating func removeFromSelection(_ itemIDs: Set<ItemID>) {
        selectedItemIDs.subtract(itemIDs)
        if let anchorItemID, itemIDs.contains(anchorItemID) {
            self.anchorItemID = nil
        }
    }

    mutating func clearSelection() {
        selectedItemIDs.removeAll()
        anchorItemID = nil
    }
}

enum ShelfSelectionReorderPolicy {
    static func reorder<ItemID: Hashable>(
        _ orderedItemIDs: [ItemID],
        moving movingItemIDs: Set<ItemID>,
        draggedItemID: ItemID,
        to targetIndex: Int
    ) -> [ItemID] {
        let movingItems = orderedItemIDs.filter { movingItemIDs.contains($0) }
        guard let draggedOffset = movingItems.firstIndex(of: draggedItemID),
              !movingItems.isEmpty else { return orderedItemIDs }

        var stationaryItems = orderedItemIDs.filter { !movingItemIDs.contains($0) }
        let insertionIndex = max(
            0,
            min(stationaryItems.count, targetIndex - draggedOffset)
        )
        stationaryItems.insert(contentsOf: movingItems, at: insertionIndex)
        return stationaryItems
    }
}
