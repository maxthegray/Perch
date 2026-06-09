import Combine
import Foundation

/// One recorded movement of an item out of the shelf: where it came from (if known),
/// where the OS dropped it, and when. Persisted to `ledger.json`, separate from item
/// metadata so the trail survives the item's removal (move-mode vends delete the item).
struct ProvenanceEntry: Codable, Equatable {
    let id: UUID
    let title: String
    /// Original source path the item was stashed from, if Perch took ownership by
    /// moving it; absent for clippings, promises, and copy fallbacks.
    let origin: String?
    /// Absolute path the OS wrote the vended file to.
    let destination: String
    let vendedAt: Date
    /// Whether the shelf kept its copy (copy mode) or handed it off (move mode).
    let wasCopy: Bool
}

/// Append-only log of item movements. Only file-promise vends expose a destination,
/// so not every drag-out produces an entry — direct-`fileURL` and text/image vends
/// are destination-blind.
@MainActor
final class ProvenanceLedger: ObservableObject {
    @Published private(set) var entries: [ProvenanceEntry] = []

    private let holding: HoldingDirectory

    init(holding: HoldingDirectory) {
        self.holding = holding
    }

    /// Load entries from `ledger.json`. A missing or unreadable file yields an empty
    /// ledger rather than failing — provenance is best-effort.
    func load() {
        guard FileManager.default.fileExists(atPath: holding.ledgerFile.path) else {
            entries = []
            return
        }
        do {
            entries = try JSONDecoder().decode(
                [ProvenanceEntry].self,
                from: Data(contentsOf: holding.ledgerFile)
            )
        } catch {
            NSLog("Perch failed to load ledger.json: \(error)")
            entries = []
        }
    }

    /// Append an entry and persist the whole ledger atomically.
    func record(_ entry: ProvenanceEntry) {
        entries.append(entry)
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: holding.ledgerFile, options: .atomic)
        } catch {
            NSLog("Perch failed to persist ledger.json: \(error)")
        }
    }

    /// The most recent recorded destination for an item, for the row breadcrumb.
    func latestEntry(for id: UUID) -> ProvenanceEntry? {
        entries.last { $0.id == id }
    }
}
