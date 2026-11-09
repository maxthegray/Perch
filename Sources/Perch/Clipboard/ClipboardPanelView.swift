import AppKit
import ClipboardCore
import SwiftUI

@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published private(set) var results: [ClipSummary] = []
    @Published private(set) var totalCount = 0
    @Published var selectedIndex = 0
    @Published var query = "" {
        didSet { refilter() }
    }
    /// Changes every time the popup opens, so the search field takes focus again.
    @Published private(set) var showCount = 0
    /// When the popup last opened; row ages are measured from it.
    @Published private(set) var shownAt = Date()
    @Published private(set) var style = MagpieStyle.defaultStyle

    var onChoose: ((ClipSummary) -> Void)?
    var onDelete: ((ClipSummary) -> Void)?

    private var clips: [ClipSummary] = []
    private var icons: [Int64: NSImage] = [:]
    private var appNames: [String: String] = [:]

    func update(clips: [ClipSummary]) {
        let ids = Set(clips.map(\.id))
        icons = icons.filter { ids.contains($0.key) }
        self.clips = clips
        totalCount = clips.count
        refilter()
    }

    func prepareForShowing(style: MagpieStyle) {
        self.style = style
        query = ""
        selectedIndex = 0
        shownAt = Date()
        showCount += 1
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    func choose(at index: Int) {
        guard results.indices.contains(index) else { return }
        onChoose?(results[index])
    }

    func chooseSelected() {
        choose(at: selectedIndex)
    }

    func deleteSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onDelete?(results[selectedIndex])
    }

    func icon(for clip: ClipSummary) -> NSImage {
        if let cached = icons[clip.id] { return cached }
        let icon = Self.makeIcon(for: clip)
        icons[clip.id] = icon
        return icon
    }

    func subtitle(for clip: ClipSummary) -> String {
        ClipRowDetail.subtitle(for: clip, appName: clip.sourceBundleID.flatMap(appName(for:)), now: shownAt)
    }

    private func appName(for bundleID: String) -> String? {
        if let cached = appNames[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        appNames[bundleID] = name
        return name
    }

    private func refilter() {
        results = ClipSearch.filter(clips, query: query)
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))
    }

    private static func makeIcon(for clip: ClipSummary) -> NSImage {
        switch clip.kind {
        case .image:
            if let data = clip.thumbnail, let image = NSImage(data: data) { return image }
        case .file:
            if let path = clip.filePaths.first { return NSWorkspace.shared.icon(forFile: path) }
        case .text, .richText:
            if let bundleID = clip.sourceBundleID,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        let symbol = clip.kind == .image ? "photo" : clip.kind == .file ? "doc" : "doc.text"
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }
}


struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            switch model.style {
            case .classic: classic
            case .detailed: detailed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { searchFocused = true }
        .onChange(of: model.showCount) { searchFocused = true }
    }

    private static let dim = Color.primary.opacity(0.55)
    private static let faint = Color.primary.opacity(0.4)

    // MARK: - Classic

    private var classic: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Self.dim)
                TextField("Type to search…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                Text("Perch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Self.faint)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .padding(.bottom, 3)

            if model.results.isEmpty {
                Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(Self.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: MagpieStyle.classicRowHeight * 1.5)
            } else {
                scrollingList(spacing: 0, padding: 5) { clip, index in
                    classicRow(clip, index: index)
                }
            }
        }
    }

    private func classicRow(_ clip: ClipSummary, index: Int) -> some View {
        let selected = index == model.selectedIndex
        return HStack(spacing: 6) {
            if clip.kind == .image {
                Image(nsImage: model.icon(for: clip))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 32, maxHeight: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            Text(clip.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Self.faint)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .frame(height: MagpieStyle.classicRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(selected ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { model.selectedIndex = index } }
        .onTapGesture { model.choose(at: index) }
    }

    // MARK: - Detailed

    private var detailed: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Perch")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.totalCount > 0 {
                    Text(model.totalCount == 1 ? "1 clip" : "\(model.totalCount) clips")
                        .font(.system(size: 11))
                        .foregroundStyle(Self.faint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 9)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Self.dim)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            if model.results.isEmpty {
                Text(model.query.isEmpty ? "Copy something — it’ll land here." : "Nothing matches “\(model.query)”.")
                    .font(.system(size: 13))
                    .foregroundStyle(Self.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollingList(spacing: 2, padding: 6) { clip, index in
                    detailedRow(clip, index: index)
                }
            }

            HStack(spacing: 14) {
                hint("↩", "Copy")
                hint("⌥⌫", "Delete")
                hint("esc", "Close")
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
            }
        }
    }

    private func detailedRow(_ clip: ClipSummary, index: Int) -> some View {
        let selected = index == model.selectedIndex
        return HStack(spacing: 10) {
            Image(nsImage: model.icon(for: clip))
                .resizable()
                .aspectRatio(contentMode: clip.kind == .image ? .fill : .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: clip.kind == .image ? 6 : 0, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.subtitle(for: clip))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if index < 9 {
                KeyHint(text: "⌘\(index + 1)", highlighted: selected)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { if $0 { model.selectedIndex = index } }
        .onTapGesture { model.choose(at: index) }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHint(text: key, highlighted: false)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Self.dim)
        }
    }

    // MARK: - Shared

    private func scrollingList<Row: View>(
        spacing: CGFloat,
        padding: CGFloat,
        @ViewBuilder row: @escaping (ClipSummary, Int) -> Row
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: spacing) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, clip in
                        row(clip, index).id(clip.id)
                    }
                }
                .padding(.horizontal, padding)
                .padding(.bottom, padding)
            }
            .onChange(of: model.selectedIndex) {
                guard model.results.indices.contains(model.selectedIndex) else { return }
                proxy.scrollTo(model.results[model.selectedIndex].id)
            }
            .onChange(of: model.showCount) {
                if let first = model.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }
}

private struct KeyHint: View {
    let text: String
    let highlighted: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Color.primary.opacity(highlighted ? 0.9 : 0.55))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(highlighted ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}
