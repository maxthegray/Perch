import AppKit

/// How the Perch Clipboard popup looks. Classic is Maccy-like: a compact menu of just the clips.
enum ClipboardStyle: String, CaseIterable, Identifiable {
    case classic
    case detailed

    static let defaultStyle = ClipboardStyle.classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .detailed: return "Detailed"
        }
    }

    static var current: ClipboardStyle {
        UserDefaults.standard.string(forKey: PerchSettings.clipboardStyle)
            .flatMap(ClipboardStyle.init(rawValue:)) ?? defaultStyle
    }

    var width: CGFloat {
        self == .classic ? 360 : 400
    }

    var cornerRadius: CGFloat {
        self == .classic ? 10 : 18
    }

    var material: NSVisualEffectView.Material {
        self == .classic ? .menu : .hudWindow
    }

    static let classicRowHeight: CGFloat = 24
    static let classicSearchHeight: CGFloat = 38
    static let classicMaxVisibleRows = 16

    /// Classic hugs its rows like a menu, growing up to `classicMaxVisibleRows` before it
    /// scrolls; Detailed is a fixed card.
    func height(forRows count: Int) -> CGFloat {
        switch self {
        case .classic:
            let rows = count == 0 ? 1.5 : CGFloat(min(count, Self.classicMaxVisibleRows))
            return Self.classicSearchHeight + rows * Self.classicRowHeight + 10
        case .detailed:
            return 470
        }
    }

    func size(forRows count: Int) -> NSSize {
        NSSize(width: width, height: height(forRows: count))
    }
}
