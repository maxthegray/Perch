import AppKit
import SwiftUI

/// A browsable log of where items have travelled — the human-facing surface over
/// `ProvenanceLedger`. Newest movements first; clicking a row reveals the dropped file
/// in Finder if it still exists.
struct HistoryView: View {
    @ObservedObject var ledger: ProvenanceLedger

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            if ledger.entries.isEmpty {
                emptyState
            } else {
                list
            }
            footer
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    private var list: some View {
        List(Array(ledger.entries.enumerated().reversed()), id: \.offset) { _, entry in
            row(entry)
                .contentShape(Rectangle())
                .onTapGesture { reveal(entry) }
        }
        .listStyle(.inset)
    }

    private func row(_ entry: ProvenanceEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.wasCopy ? "doc.on.doc" : "arrow.right.doc.on.clipboard")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(trail(entry))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(Self.dateFormatter.string(from: entry.vendedAt))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack {
            Text("\(ledger.entries.count) move\(ledger.entries.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear History") { ledger.clear() }
                .controlSize(.small)
                .disabled(ledger.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No movements yet")
                .font(.system(size: 13, weight: .medium))
            Text("Drag a file out of the shelf into a folder and it'll show up here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func trail(_ entry: ProvenanceEntry) -> String {
        let destination = folderName(entry.destination)
        if let origin = entry.origin {
            return "\(folderName(origin)) → \(destination)"
        }
        return "→ \(destination)"
    }

    /// The parent folder name of a file path, for compact display.
    private func folderName(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    private func reveal(_ entry: ProvenanceEntry) {
        let url = URL(fileURLWithPath: entry.destination)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
