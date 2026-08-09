import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI view for a single stored item. Its anatomy (icon size, title, subtitle,
/// separators, height) is driven by the active `ShelfTheme`, so Glass and Minimal read
/// as genuinely different looks. Pinned to exactly `theme.rowHeight` so the window can
/// size to its contents precisely. Hover state is supplied by AppKit (`ShelfHostView`),
/// since the host view intercepts mouse events; the delete "✕" is drawn here but its
/// click is handled in AppKit too.
struct ItemRowView: View {
    let item: StoredItem
    let theme: ShelfTheme
    let isHovered: Bool
    let isSelected: Bool
    /// Whether this row is the one being dragged to reorder (lifted styling).
    let isDragging: Bool
    /// Whether this row is mid-delete: it pops up slightly (affirmative bounce) just
    /// before the removal transition shrinks it away.
    let isDeleting: Bool
    /// A real Quick Look content preview, if one has been generated; otherwise nil and
    /// we fall back to the file-type icon.
    let thumbnail: NSImage?
    /// Whether to draw a hairline separator beneath this row (Minimal; not the last row).
    let showsSeparator: Bool
    /// When false, the name/subtitle are hidden and the row shows just a centered icon.
    let showsLabels: Bool
    /// The populated shelf hugs its widest title; every row then fills that compact
    /// width so the stack has clean, consistent left and right edges.
    let maximumWidth: CGFloat
    /// Presentation title selected by SmartNameStore. Screenshot rows begin with a
    /// generic label and later crossfade to the generated name in the same geometry.
    let displayTitle: String
    let isNameAnalysisPending: Bool
    let transformResultDetail: String?
    let showsTrailingActions: Bool
    /// Short name of the folder this item has repeatedly been dragged to, if Perch has
    /// learned one. Its presence adds the file-it button and the destination subtitle.
    let learnedDestinationName: String?

    var body: some View {
        HStack(spacing: showsLabels ? RowMetrics.labeledRowSpacing : 0) {
            icon

            if showsLabels {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(size: theme.titleSize, weight: theme.titleWeight))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)

                    // Keep this line present before and after analysis. Removing it when
                    // the Smart Name arrived made the title jump vertically even when
                    // the outer card width was held steady.
                    if theme.showsSubtitle {
                        Text(displayedSubtitle)
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contentTransition(.opacity)
                    }
                }
            }
        }
        .padding(
            .horizontal,
            showsLabels ? RowMetrics.labeledRowHorizontalPadding : 0
        )
        .frame(
            width: rowWidth,
            alignment: showsLabels ? .leading : .center
        )
        .frame(
            minHeight: theme.rowHeight,
            maxHeight: theme.rowHeight,
            alignment: showsLabels ? .leading : .center
        )
        .background(
            RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : (isHovered ? theme.rowHoverFill : theme.rowFill))
        )
        .overlay(alignment: .bottom) { separator }
        .overlay(alignment: .trailing) { trailingActions }
        .contentShape(Rectangle())
        .scaleEffect(isDeleting ? 1.06 : (isDragging ? 1.03 : 1))
        .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 6, y: 3)
        .opacity(isDragging ? 0.95 : 1)
        .zIndex(isDragging || isDeleting ? 1 : 0)
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .animation(.easeOut(duration: 0.13), value: isSelected)
        .animation(.easeOut(duration: 0.2), value: thumbnail != nil)
        .animation(.easeOut(duration: 0.18), value: displayTitle)
        .animation(.easeOut(duration: 0.18), value: learnedDestinationName)
        .animation(.easeOut(duration: 0.18), value: transformResultDetail)
        .animation(.easeOut(duration: 0.18), value: isNameAnalysisPending)
        .animation(.easeOut(duration: 0.16), value: isDragging)
        .animation(.spring(response: 0.16, dampingFraction: 0.5), value: isDeleting)
    }

    private var rowWidth: CGFloat {
        maximumWidth
    }

    /// A real preview is shown as a small rounded "photo" tile; a generic file icon is
    /// shown at its natural shape. Size/flatness follow the theme.
    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: theme.iconSize, height: theme.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: theme.iconCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.iconCornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(theme.iconShadow ? 0.2 : 0), radius: 1.5, y: 0.5)
                .transition(.opacity)
        } else {
            Image(nsImage: item.iconImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: theme.iconSize, height: theme.iconSize)
                .shadow(color: .black.opacity(theme.iconShadow ? 0.14 : 0), radius: 1.5, y: 0.5)
        }
    }

    @ViewBuilder
    private var separator: some View {
        if showsSeparator {
            Rectangle()
                .fill(theme.separatorColor)
                .frame(height: 0.5)
                .padding(.leading, theme.iconSize + 20)
                .padding(.trailing, 10)
        }
    }

    /// The file-it button sits inboard of the delete button, so the destructive action
    /// keeps the corner position muscle memory already points at.
    @ViewBuilder
    private var trailingActions: some View {
        if theme.showsDeleteButton && showsLabels && showsTrailingActions && isHovered {
            HStack(spacing: RowMetrics.trailingActionSpacing) {
                if learnedDestinationName != nil {
                    circularAction(symbol: "folder", isProminent: true)
                }
                circularAction(symbol: rowActionSymbol, isProminent: false)
            }
            .padding(.trailing, RowMetrics.deleteTrailingInset)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }

    private func circularAction(symbol: String, isProminent: Bool) -> some View {
        ZStack {
            Circle().fill(.thinMaterial)
            Circle().stroke(.white.opacity(0.18), lineWidth: 0.5)
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(isProminent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
        .frame(width: RowMetrics.deleteDiameter, height: RowMetrics.deleteDiameter)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    /// Files whose origin is known really go back when clicked, so show a return
    /// arrow. Clippings/promises have no place to return and are removed, retaining ✕.
    private var rowActionSymbol: String {
        item.metadata.originPaths?.isEmpty == false
            ? "arrow.uturn.backward"
            : "xmark"
    }

    private var subtitle: String {
        if let name = item.metadata.backingFileNames.first,
           name.contains("."),
           let ext = name.split(separator: ".").last {
            return ext.uppercased()
        }
        if let type = item.metadata.primaryFileType,
           let contentType = UTType(type),
           let description = contentType.localizedDescription {
            return description.capitalized
        }
        return "Clipping"
    }

    /// The learned destination replaces the file-type line: where this is going is more
    /// useful than what it is, and the row has room for exactly one of them.
    private var displayedSubtitle: String {
        if isNameAnalysisPending {
            return "Finding a useful name…"
        }
        if let transformResultDetail {
            return transformResultDetail
        }
        if let learnedDestinationName {
            return "→ \(learnedDestinationName)"
        }
        return subtitle
    }
}
