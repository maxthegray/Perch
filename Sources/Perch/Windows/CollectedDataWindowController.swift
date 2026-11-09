import AppKit
import SwiftUI

/// A read-only look at exactly what a Labs feature has stored on this Mac.
@MainActor
final class CollectedDataWindowController {
    private var windows: [String: NSWindow] = [:]

    func show(title: String, databaseURL: URL) {
        if let window = windows[title] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: CollectedDataView(title: title, databaseURL: databaseURL)
            )
        )
        window.title = "\(title) — Collected Data"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        windows[title] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct CollectedDataView: View {
    let title: String
    let databaseURL: URL

    @State private var tables: [CollectedTable] = []
    @State private var selection: String?
    @State private var errorMessage: String?

    private static let columnWidth: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Everything \(title) has stored on this Mac, exactly as saved. Nothing here is ever sent anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                }
                .disabled(!FileManager.default.fileExists(atPath: databaseURL.path))
                Button("Refresh", action: load)
            }
            .padding(12)

            Divider()

            if let errorMessage {
                message(errorMessage)
            } else if tables.isEmpty {
                message("Nothing has been collected.")
            } else {
                HSplitView {
                    List(tables, selection: $selection) { table in
                        HStack {
                            Text(table.name)
                            Spacer()
                            Text("\(table.totalRows)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .tag(table.name)
                    }
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)

                    if let table = tables.first(where: { $0.name == selection }) {
                        rows(of: table)
                    } else {
                        message("Pick a table.")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        .onAppear(perform: load)
    }

    private func rows(of table: CollectedTable) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if table.totalRows > table.rows.count {
                Text("Showing the newest \(table.rows.count) of \(table.totalRows) rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    Section {
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                            line(row, bold: false)
                                .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : .clear)
                        }
                    } header: {
                        line(table.columns, bold: true)
                            .background(.bar)
                    }
                }
            }
            .defaultScrollAnchor(.topLeading)
        }
    }

    private func line(_ cells: [String], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(size: 11, weight: bold ? .semibold : .regular, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(width: Self.columnWidth, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        do {
            tables = try CollectedDataReader.read(databaseURL: databaseURL)
            errorMessage = nil
            if selection == nil || !tables.contains(where: { $0.name == selection }) {
                selection = tables.first?.name
            }
        } catch {
            tables = []
            errorMessage = "The data could not be read: \(error.localizedDescription)"
        }
    }
}
