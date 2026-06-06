import Foundation

/// Resolves and owns the on-disk layout under
/// `~/Library/Application Support/Perch/`.
struct HoldingDirectory {
    /// The Perch root inside Application Support.
    let root: URL

    /// Resolve (creating if absent) the standard holding directory.
    static func standard() throws -> HoldingDirectory {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let holding = HoldingDirectory(
            root: applicationSupport.appendingPathComponent("Perch", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: holding.itemsDir, withIntermediateDirectories: true)
        return holding
    }

    var itemsDir: URL {
        root.appendingPathComponent("items", isDirectory: true)
    }

    var indexFile: URL {
        root.appendingPathComponent("index.json", isDirectory: false)
    }

    func itemDir(_ id: UUID) -> URL {
        itemsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }
}
