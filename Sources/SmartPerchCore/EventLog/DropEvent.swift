import Foundation
import GRDB

/// Best-effort identity of the app that initiated a drop.
public struct SourceApplicationContext: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let displayName: String?

    public init(bundleIdentifier: String?, displayName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

/// Identity and context captured once at the start of a drop.
///
/// One physical drag has a shared batch ID. Each shelf item produced by that drag gets
/// its own event ID so it can be finalized independently.
public struct DropRecordingContext: Equatable, Sendable {
    public let eventID: UUID
    public let batchID: UUID
    public let occurredAt: Date
    public let sourceApplication: SourceApplicationContext?

    public init(
        eventID: UUID = UUID(),
        batchID: UUID,
        occurredAt: Date,
        sourceApplication: SourceApplicationContext?
    ) {
        self.eventID = eventID
        self.batchID = batchID
        self.occurredAt = occurredAt
        self.sourceApplication = sourceApplication
    }
}

public enum DropPayloadKind: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case file
    case filePromise
    case clipping
    case mixed
    case recentArrival
    case transform
}

/// OCR progresses asynchronously after the drop is safely stored. Keeping an explicit
/// state avoids treating "not eligible", "no text found", and "failed" as the same
/// nil value.
public enum OCRProcessingState: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case notEvaluated
    case notEligible
    case pending
    case completed
    case noText
    case failed
}

public enum FilenameSuggestionState: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    case notEvaluated
    case unavailable
    case available
    case accepted
    case dismissed
}

extension FileCategory: DatabaseValueConvertible {}

/// One shelf item produced by a drop. A multi-file Finder drag creates several of
/// these with the same batch ID; a grouped file promise can create one event with
/// several `DroppedFileEvent` children.
public struct DropEvent: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    public static let databaseTableName = "drop_events"
    public static let currentSchemaVersion = 5

    public let id: UUID
    public let batchID: UUID
    public let shelfItemID: UUID
    public let occurredAtMilliseconds: Int64
    public let sourceAppBundleIdentifier: String?
    public let sourceAppName: String?
    public let payloadKind: DropPayloadKind
    public let schemaVersion: Int

    public init(
        id: UUID,
        batchID: UUID,
        shelfItemID: UUID,
        occurredAtMilliseconds: Int64,
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?,
        payloadKind: DropPayloadKind,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.id = id
        self.batchID = batchID
        self.shelfItemID = shelfItemID
        self.occurredAtMilliseconds = occurredAtMilliseconds
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.payloadKind = payloadKind
        self.schemaVersion = schemaVersion
    }

    enum CodingKeys: String, CodingKey {
        case id
        case batchID = "batch_id"
        case shelfItemID = "shelf_item_id"
        case occurredAtMilliseconds = "occurred_at_ms"
        case sourceAppBundleIdentifier = "source_app_bundle_identifier"
        case sourceAppName = "source_app_name"
        case payloadKind = "payload_kind"
        case schemaVersion = "schema_version"
    }
}

/// The metadata and first-stage classification of one finalized file, plus its
/// asynchronous OCR enrichment state.
public struct DroppedFileEvent: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    public static let databaseTableName = "dropped_files"

    public let fileID: UUID
    public let dropEventID: UUID
    public let ordinal: Int
    public let displayName: String
    public let pathExtension: String
    public let contentTypeIdentifier: String?
    public let byteCount: Int64?
    public let isDirectory: Bool?
    public let isScreenCapture: Bool?
    public let category: FileCategory
    public let classifierIdentifier: String
    public let classifierVersion: Int
    public let ocrState: OCRProcessingState
    public let ocrText: String?
    public let ocrCompletedAtMilliseconds: Int64?
    public let ocrDurationMilliseconds: Int64?
    public let screenshotCaptureContextJSON: String?
    public let ocrLayoutJSON: String?
    public let smartLabel: String?
    public let filenameSuggestion: String?
    public let filenameSuggestionState: FilenameSuggestionState
    public let filenameSuggesterIdentifier: String?
    public let filenameSuggesterVersion: Int?
    public let filenameSuggestionDecidedAtMilliseconds: Int64?
    public let acceptedFilename: String?

    public init(
        fileID: UUID,
        dropEventID: UUID,
        ordinal: Int,
        displayName: String,
        pathExtension: String,
        contentTypeIdentifier: String?,
        byteCount: Int64?,
        isDirectory: Bool?,
        isScreenCapture: Bool?,
        category: FileCategory,
        classifierIdentifier: String,
        classifierVersion: Int,
        ocrState: OCRProcessingState,
        ocrText: String?,
        ocrCompletedAtMilliseconds: Int64?,
        ocrDurationMilliseconds: Int64?,
        screenshotCaptureContextJSON: String? = nil,
        ocrLayoutJSON: String? = nil,
        smartLabel: String? = nil,
        filenameSuggestion: String? = nil,
        filenameSuggestionState: FilenameSuggestionState = .notEvaluated,
        filenameSuggesterIdentifier: String? = nil,
        filenameSuggesterVersion: Int? = nil,
        filenameSuggestionDecidedAtMilliseconds: Int64? = nil,
        acceptedFilename: String? = nil
    ) {
        self.fileID = fileID
        self.dropEventID = dropEventID
        self.ordinal = ordinal
        self.displayName = displayName
        self.pathExtension = pathExtension
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.isDirectory = isDirectory
        self.isScreenCapture = isScreenCapture
        self.category = category
        self.classifierIdentifier = classifierIdentifier
        self.classifierVersion = classifierVersion
        self.ocrState = ocrState
        self.ocrText = ocrText
        self.ocrCompletedAtMilliseconds = ocrCompletedAtMilliseconds
        self.ocrDurationMilliseconds = ocrDurationMilliseconds
        self.screenshotCaptureContextJSON = screenshotCaptureContextJSON
        self.ocrLayoutJSON = ocrLayoutJSON
        self.smartLabel = smartLabel
        self.filenameSuggestion = filenameSuggestion
        self.filenameSuggestionState = filenameSuggestionState
        self.filenameSuggesterIdentifier = filenameSuggesterIdentifier
        self.filenameSuggesterVersion = filenameSuggesterVersion
        self.filenameSuggestionDecidedAtMilliseconds = filenameSuggestionDecidedAtMilliseconds
        self.acceptedFilename = acceptedFilename
    }

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case dropEventID = "drop_event_id"
        case ordinal
        case displayName = "display_name"
        case pathExtension = "path_extension"
        case contentTypeIdentifier = "content_type_identifier"
        case byteCount = "byte_count"
        case isDirectory = "is_directory"
        case isScreenCapture = "is_screen_capture"
        case category
        case classifierIdentifier = "classifier_identifier"
        case classifierVersion = "classifier_version"
        case ocrState = "ocr_state"
        case ocrText = "ocr_text"
        case ocrCompletedAtMilliseconds = "ocr_completed_at_ms"
        case ocrDurationMilliseconds = "ocr_duration_ms"
        case screenshotCaptureContextJSON = "screenshot_capture_context_json"
        case ocrLayoutJSON = "ocr_layout_json"
        case smartLabel = "smart_label"
        case filenameSuggestion = "filename_suggestion"
        case filenameSuggestionState = "filename_suggestion_state"
        case filenameSuggesterIdentifier = "filename_suggester_identifier"
        case filenameSuggesterVersion = "filename_suggester_version"
        case filenameSuggestionDecidedAtMilliseconds = "filename_suggestion_decided_at_ms"
        case acceptedFilename = "accepted_filename"
    }

    public var screenshotCaptureContext: ScreenshotCaptureContext? {
        screenshotCaptureContextJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap {
                try? JSONDecoder().decode(
                    ScreenshotCaptureContext.self,
                    from: $0
                )
            }
    }
}

/// An unresolved suggestion ready to be shown for a shelf item.
public struct AvailableFilenameSuggestion: Equatable, Sendable {
    public let fileID: UUID
    public let shelfItemID: UUID
    public let originalFilename: String
    public let displayName: String
    public let suggestedFilename: String

    public init(
        fileID: UUID,
        shelfItemID: UUID,
        originalFilename: String,
        displayName: String,
        suggestedFilename: String
    ) {
        self.fileID = fileID
        self.shelfItemID = shelfItemID
        self.originalFilename = originalFilename
        self.displayName = displayName
        self.suggestedFilename = suggestedFilename
    }
}

/// Query shape consumed by future pure behavior policies.
public struct RecordedDrop: Equatable, Sendable {
    public let event: DropEvent
    public let files: [DroppedFileEvent]

    public init(event: DropEvent, files: [DroppedFileEvent]) {
        self.event = event
        self.files = files
    }
}
