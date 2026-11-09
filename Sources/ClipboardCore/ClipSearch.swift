import Foundation

/// Fuzzy filtering for the clipboard popup. Clips containing the query rank first, then
/// clips whose title holds the query's characters in order; within each tier the input's
/// (recency) order is kept.
public enum ClipSearch {
    public static func filter(_ clips: [ClipSummary], query: String) -> [ClipSummary] {
        let needle = normalize(query).filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return clips }

        let phrase = normalize(query.trimmingCharacters(in: .whitespaces))
        var substring: [ClipSummary] = []
        var subsequence: [ClipSummary] = []
        for clip in clips {
            if normalize(clip.searchText).contains(phrase) || normalize(clip.title).contains(phrase) {
                substring.append(clip)
            } else if isSubsequence(needle, of: normalize(clip.title)) {
                subsequence.append(clip)
            }
        }
        return substring + subsequence
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
