import Foundation
import GRDB

/// The kind of destination that accepted an item leaving Perch.
public enum RouteDestinationKind: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case folder
    case application
}

/// A successful, locally observed destination. Folder paths are deliberately kept
/// exact in the on-device database; application routes prefer the stable bundle ID
/// and retain the display name as a readable fallback.
public enum RouteDestination: Codable, Equatable, Hashable, Sendable {
    case folder(path: String)
    case application(bundleIdentifier: String?, name: String)

    public var kind: RouteDestinationKind {
        switch self {
        case .folder:
            return .folder
        case .application:
            return .application
        }
    }

    /// Stable grouping identity used by the pure pattern detector.
    public var normalizedIdentifier: String {
        switch self {
        case let .folder(path):
            let standardized = (path as NSString).standardizingPath
            return "folder:\(standardized)"
        case let .application(bundleIdentifier?, _):
            return "application:bundle:\(bundleIdentifier.normalizedRouteComponent)"
        case let .application(nil, name):
            return "application:name:\(name.normalizedRouteComponent)"
        }
    }

    fileprivate var folderPath: String? {
        guard case let .folder(path) = self else { return nil }
        return path
    }

    fileprivate var applicationBundleIdentifier: String? {
        guard case let .application(bundleIdentifier, _) = self else { return nil }
        return bundleIdentifier
    }

    fileprivate var applicationName: String? {
        guard case let .application(_, name) = self else { return nil }
        return name
    }
}

/// Evidence that established the canonical destination for a drag.
public enum RouteCaptureMethod: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case filePromiseWrite = "file_promise_write"
    case applicationWindow = "application_window"
    /// Perch performed the move itself, so the destination is known exactly rather
    /// than observed.
    case perchFiling = "perch_filing"
}

public enum RouteTransferMode: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case copy
    case move
}

/// What caused an item to travel to its destination.
///
/// Only `manualDrag` is evidence of where the user wants things to go. A route the
/// user merely confirmed by clicking Perch's own suggestion would otherwise reinforce
/// the pattern that produced it, so `RoutePatternDetector` ignores those — see
/// `RoutePatternDetector.detectPatterns`.
public enum RouteEventOrigin: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case manualDrag = "manual_drag"
    case acceptedSuggestion = "accepted_suggestion"
}

/// One successful item's trip out of Perch. A multi-item drag creates one row for
/// each item and gives every row the same route session ID.
public struct ItemRouteEvent: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    public static let databaseTableName = "item_route_events"
    public static let currentSchemaVersion = 1

    public let id: UUID
    public let routeSessionID: UUID
    public let shelfItemID: UUID
    public let successfulDropAtMilliseconds: Int64
    public let dwellTimeMilliseconds: Int64
    public let destination: RouteDestination
    public let captureMethod: RouteCaptureMethod
    public let transferMode: RouteTransferMode
    public let sourceAppBundleIdentifier: String?
    public let sourceAppName: String?
    public let category: FileCategory?
    public let origin: RouteEventOrigin
    public let schemaVersion: Int

    public init(
        id: UUID = UUID(),
        routeSessionID: UUID,
        shelfItemID: UUID,
        successfulDropAtMilliseconds: Int64,
        dwellTimeMilliseconds: Int64,
        destination: RouteDestination,
        captureMethod: RouteCaptureMethod,
        transferMode: RouteTransferMode,
        sourceAppBundleIdentifier: String? = nil,
        sourceAppName: String? = nil,
        category: FileCategory? = nil,
        origin: RouteEventOrigin = .manualDrag,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.id = id
        self.routeSessionID = routeSessionID
        self.shelfItemID = shelfItemID
        self.successfulDropAtMilliseconds = successfulDropAtMilliseconds
        self.dwellTimeMilliseconds = dwellTimeMilliseconds
        self.destination = destination
        self.captureMethod = captureMethod
        self.transferMode = transferMode
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.category = category
        self.origin = origin
        self.schemaVersion = schemaVersion
    }

    public var wasCopy: Bool {
        transferMode == .copy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        routeSessionID = try container.decode(UUID.self, forKey: .routeSessionID)
        shelfItemID = try container.decode(UUID.self, forKey: .shelfItemID)
        successfulDropAtMilliseconds = try container.decode(
            Int64.self,
            forKey: .successfulDropAtMilliseconds
        )
        dwellTimeMilliseconds = try container.decode(
            Int64.self,
            forKey: .dwellTimeMilliseconds
        )

        let kind = try container.decode(RouteDestinationKind.self, forKey: .destinationKind)
        switch kind {
        case .folder:
            destination = .folder(
                path: try container.decode(String.self, forKey: .destinationFolderPath)
            )
        case .application:
            destination = .application(
                bundleIdentifier: try container.decodeIfPresent(
                    String.self,
                    forKey: .destinationAppBundleIdentifier
                ),
                name: try container.decode(String.self, forKey: .destinationAppName)
            )
        }

        captureMethod = try container.decode(RouteCaptureMethod.self, forKey: .captureMethod)
        transferMode = try container.decode(RouteTransferMode.self, forKey: .transferMode)
        sourceAppBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .sourceAppBundleIdentifier
        )
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        category = try container.decodeIfPresent(FileCategory.self, forKey: .category)
        // Rows written before the origin column existed are all real user drags.
        origin = try container.decodeIfPresent(RouteEventOrigin.self, forKey: .origin)
            ?? .manualDrag
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(routeSessionID, forKey: .routeSessionID)
        try container.encode(shelfItemID, forKey: .shelfItemID)
        try container.encode(
            successfulDropAtMilliseconds,
            forKey: .successfulDropAtMilliseconds
        )
        try container.encode(dwellTimeMilliseconds, forKey: .dwellTimeMilliseconds)
        try container.encode(destination.kind, forKey: .destinationKind)
        try container.encodeIfPresent(
            destination.folderPath,
            forKey: .destinationFolderPath
        )
        try container.encodeIfPresent(
            destination.applicationBundleIdentifier,
            forKey: .destinationAppBundleIdentifier
        )
        try container.encodeIfPresent(
            destination.applicationName,
            forKey: .destinationAppName
        )
        try container.encode(captureMethod, forKey: .captureMethod)
        try container.encode(transferMode, forKey: .transferMode)
        try container.encodeIfPresent(
            sourceAppBundleIdentifier,
            forKey: .sourceAppBundleIdentifier
        )
        try container.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(origin, forKey: .origin)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    func addingLearningContext(
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?,
        category: FileCategory?
    ) -> ItemRouteEvent {
        ItemRouteEvent(
            id: id,
            routeSessionID: routeSessionID,
            shelfItemID: shelfItemID,
            successfulDropAtMilliseconds: successfulDropAtMilliseconds,
            dwellTimeMilliseconds: dwellTimeMilliseconds,
            destination: destination,
            captureMethod: captureMethod,
            transferMode: transferMode,
            sourceAppBundleIdentifier: self.sourceAppBundleIdentifier
                ?? sourceAppBundleIdentifier,
            sourceAppName: self.sourceAppName ?? sourceAppName,
            category: self.category ?? category,
            origin: origin,
            schemaVersion: schemaVersion
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case routeSessionID = "route_session_id"
        case shelfItemID = "shelf_item_id"
        case successfulDropAtMilliseconds = "successful_drop_at_ms"
        case dwellTimeMilliseconds = "dwell_time_ms"
        case destinationKind = "destination_kind"
        case destinationFolderPath = "destination_folder_path"
        case destinationAppBundleIdentifier = "destination_app_bundle_identifier"
        case destinationAppName = "destination_app_name"
        case captureMethod = "capture_method"
        case transferMode = "transfer_mode"
        case sourceAppBundleIdentifier = "source_app_bundle_identifier"
        case sourceAppName = "source_app_name"
        case category
        case origin
        case schemaVersion = "schema_version"
    }
}

private extension String {
    var normalizedRouteComponent: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
