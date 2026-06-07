import Combine
import CoreGraphics
import Foundation

/// Which row the pointer is currently over. Updated by `ShelfHostView`'s AppKit
/// mouse-tracking (the SwiftUI content never receives mouse events, since the host
/// view intercepts hit-testing) and observed by the SwiftUI rows to show the hover
/// highlight + delete button.
@MainActor
final class RowInteractionState: ObservableObject {
    @Published var hoveredItemID: UUID?
}

/// Layout constants shared between the SwiftUI row rendering (`ItemRowView`) and the
/// AppKit hit-testing (`ShelfHostView`) so the drag target and the delete button line
/// up with what's drawn. Pitch-related spacing/padding live on `ShelfTheme`.
enum RowMetrics {
    /// Each row is pinned to exactly this height (via `.frame(height:)`), so the
    /// window-sizing math in ShelfController is exact and rows never clip.
    static let height: CGFloat = 50
    /// Delete button diameter.
    static let deleteDiameter: CGFloat = 20
    /// Trailing inset of the delete button from the row's right edge.
    static let deleteTrailingInset: CGFloat = 7
}
