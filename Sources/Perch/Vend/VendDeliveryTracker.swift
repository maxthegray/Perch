import Foundation

/// Reconciles the two independent signals that decide whether a vended row may leave
/// the shelf: AppKit's drag-ended callback (on the main actor) and each item's
/// file-promise write result (delivered from the writer's background operation queue).
///
/// The two arrive in either order, and a multi-item drag resolves per item — one
/// destination refusing one write must not restore the siblings it accepted. Both facts
/// are recorded here and applied once the other side is known, so a failure that beats
/// the drag-ended callback is remembered rather than lost, and one that follows it
/// restores exactly the row that failed.
@MainActor
final class VendDeliveryTracker {
    private enum Delivery {
        case pending
        case delivered
        case failed
    }

    /// Kept in selection order so retirement follows the order the rows were vended in
    /// rather than a dictionary's iteration order.
    private let items: [StoredItem]
    /// Copy-mode vends never retire a row, so there is nothing to reconcile.
    private let appliesMoveSemantics: Bool
    private let retire: (StoredItem) -> Void
    private let restore: (StoredItem) -> Void

    private var deliveryByID: [UUID: Delivery]
    /// Nil until the drag ends; then true for a real external landing.
    private var landed: Bool?

    init(
        items: [StoredItem],
        appliesMoveSemantics: Bool,
        retire: @escaping (StoredItem) -> Void,
        restore: @escaping (StoredItem) -> Void
    ) {
        var seenIDs: Set<UUID> = []
        self.items = items.filter { seenIDs.insert($0.id).inserted }
        self.appliesMoveSemantics = appliesMoveSemantics
        self.retire = retire
        self.restore = restore
        deliveryByID = Dictionary(uniqueKeysWithValues: self.items.map { ($0.id, .pending) })
    }

    /// The destination took delivery of this item's promised file.
    func promiseDidWrite(itemID: UUID) {
        record(.delivered, for: itemID)
    }

    /// The destination accepted the drop but the promised write failed (a denied
    /// sandbox grant, a full volume, a vanished folder).
    func promiseDidFail(itemID: UUID) {
        record(.failed, for: itemID)
    }

    /// The drag landed somewhere outside Perch: every item whose delivery has not
    /// already failed leaves the shelf.
    func dragDidLand() {
        guard landed == nil else { return }
        landed = true
        guard appliesMoveSemantics else { return }
        for item in items where deliveryByID[item.id] != .failed {
            retire(item)
        }
    }

    /// The drag was cancelled or came back to Perch — nothing leaves the shelf, and a
    /// late promise result can no longer change that.
    func dragDidNotLand() {
        guard landed == nil else { return }
        landed = false
    }

    private func record(_ delivery: Delivery, for itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }),
              deliveryByID[itemID] != delivery else { return }
        deliveryByID[itemID] = delivery

        // Before the drag ends this is pure bookkeeping; `dragDidLand` reads it. After
        // an external landing the row is already gone, so a failure has to put it back.
        guard landed == true, appliesMoveSemantics, delivery == .failed else { return }
        restore(item)
    }
}
