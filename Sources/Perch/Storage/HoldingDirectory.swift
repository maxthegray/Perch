import Foundation

/// Resolves and owns the on-disk layout under
/// `~/Library/Application Support/Perch/`.
struct HoldingDirectory {
    /// The Perch root inside Application Support.
    let root: URL

    /// Resolve (creating if absent) the standard holding directory.
    static func standard() throws -> HoldingDirectory {
        fatalError("unimplemented")
    }

    var itemsDir: URL {
        fatalError("unimplemented")
    }

    var indexFile: URL {
        fatalError("unimplemented")
    }

    func itemDir(_ id: UUID) -> URL {
        fatalError("unimplemented")
    }
}
