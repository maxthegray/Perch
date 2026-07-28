import Foundation

/// Stable, deliberately broad buckets used by Smart Perch policies.
///
/// Raw values are persisted in the event log, so cases should not be renamed after
/// shipping. Add a new case when a future classifier needs more precision.
public enum FileCategory: String, Codable, CaseIterable, Sendable {
    case document
    case image
    case installer
    case archive
    case code
    case media
    case other
}
