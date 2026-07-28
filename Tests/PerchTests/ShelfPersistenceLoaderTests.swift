import Foundation
import XCTest
@testable import Perch

@MainActor
final class ShelfPersistenceLoaderTests: XCTestCase {
    func testCorruptItemIndexStillLoadsAndPreservesLedgerHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ShelfPersistenceLoaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let holding = HoldingDirectory(root: root)
        try FileManager.default.createDirectory(
            at: holding.itemsDir,
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: holding.indexFile)

        let originalEntry = ProvenanceEntry(
            id: UUID(),
            title: "original.png",
            origin: "/tmp/original.png",
            destination: "/tmp/destination/original.png",
            vendedAt: Date(timeIntervalSince1970: 1_700_000_000),
            wasCopy: false
        )
        try JSONEncoder().encode([originalEntry]).write(
            to: holding.ledgerFile,
            options: .atomic
        )

        let store = ItemStore(holding: holding)
        let ledger = ProvenanceLedger(holding: holding)
        XCTAssertThrowsError(
            try ShelfPersistenceLoader.load(store: store, ledger: ledger)
        )
        XCTAssertEqual(ledger.entries, [originalEntry])

        let laterEntry = ProvenanceEntry(
            id: UUID(),
            title: "later.png",
            origin: nil,
            destination: "/tmp/destination/later.png",
            vendedAt: Date(timeIntervalSince1970: 1_700_000_100),
            wasCopy: true
        )
        ledger.record(laterEntry)

        let persisted = try JSONDecoder().decode(
            [ProvenanceEntry].self,
            from: Data(contentsOf: holding.ledgerFile)
        )
        XCTAssertEqual(persisted, [originalEntry, laterEntry])
    }
}
