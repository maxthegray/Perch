import Foundation
import GRDB

public enum ArrivalSessionAction: String, Codable, DatabaseValueConvertible, Sendable {
    case expanded
    case adoptedOne
    case adoptedAll
    case dismissedOne
    case dismissedAll
}

/// A deliberate user response to a recent-arrival session. These records are the
/// behavioral signal for future suggestions; merely noticing a file is not treated
/// as intent.
public struct ArrivalSessionInteraction: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    public static let databaseTableName = "arrival_session_interactions"

    public let id: UUID
    public let sessionID: UUID
    public let occurredAtMilliseconds: Int64
    public let locationIdentifier: String
    public let action: ArrivalSessionAction
    public let totalFileCount: Int
    public let affectedFileCount: Int

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        occurredAtMilliseconds: Int64,
        locationIdentifier: String,
        action: ArrivalSessionAction,
        totalFileCount: Int,
        affectedFileCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.occurredAtMilliseconds = occurredAtMilliseconds
        self.locationIdentifier = locationIdentifier
        self.action = action
        self.totalFileCount = totalFileCount
        self.affectedFileCount = affectedFileCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case occurredAtMilliseconds = "occurred_at_ms"
        case locationIdentifier = "location_identifier"
        case action
        case totalFileCount = "total_file_count"
        case affectedFileCount = "affected_file_count"
    }
}
