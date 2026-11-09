import ClipboardCore
import Foundation

/// The dim second line under a clip in Magpie: where it came from and when.
enum ClipRowDetail {
    static func subtitle(for clip: ClipSummary, appName: String?, now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if clip.kind == .file {
            if clip.filePaths.count > 1 {
                parts.append("\(clip.filePaths.count) files")
            } else if let path = clip.filePaths.first {
                parts.append(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)
            }
        } else if let appName {
            parts.append(appName)
        }
        parts.append(age(of: clip.lastCopiedAt, now: now, calendar: calendar))
        return parts.joined(separator: " · ")
    }

    static func age(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<(12 * 3600): return "\(Int(seconds / 3600))h ago"
        default: break
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
