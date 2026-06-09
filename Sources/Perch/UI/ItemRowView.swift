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
    /// Whether this row is the one being dragged to reorder (lifted styling).
    let isDragging: Bool
    /// A real Quick Look content preview, if one has been generated; otherwise nil and
    /// we fall back to the file-type icon.
    let thumbnail: NSImage?
    /// Whether to draw a hairline separator beneath this row (Minimal; not the last row).
    let showsSeparator: Bool
    /// When false, the name/subtitle are hidden and the row shows just a centered icon.
    let showsLabels: Bool
    /// An origin → destination provenance breadcrumb, shown in place of the type
    /// subtitle when the item's travel is known; nil falls back to the type label.
    let breadcrumb: String?

    var body: some View {
        HStack(spacing: showsLabels ? 10 : 0) {
            icon

            if showsLabels {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.metadata.title)
                        .font(.system(size: theme.titleSize, weight: theme.titleWeight))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if theme.showsSubtitle {
                        Text(breadcrumb ?? subtitle)
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, showsLabels ? 10 : 0)
        .frame(
            maxWidth: .infinity,
            minHeight: theme.rowHeight,
            maxHeight: theme.rowHeight,
            alignment: showsLabels ? .leading : .center
        )
        .background(
            RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
                .fill(isHovered ? theme.rowHoverFill : theme.rowFill)
        )
        .overlay(alignment: .bottom) { separator }
        .overlay(alignment: .trailing) { deleteButton }
        .contentShape(Rectangle())
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 6, y: 3)
        .opacity(isDragging ? 0.95 : 1)
        .zIndex(isDragging ? 1 : 0)
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: thumbnail != nil)
        .animation(.easeOut(duration: 0.16), value: isDragging)
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

    @ViewBuilder
    private var deleteButton: some View {
        if theme.showsDeleteButton && showsLabels && isHovered {
            ZStack {
                Circle().fill(.thinMaterial)
                Circle().stroke(.white.opacity(0.18), lineWidth: 0.5)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: RowMetrics.deleteDiameter, height: RowMetrics.deleteDiameter)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .padding(.trailing, RowMetrics.deleteTrailingInset)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
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
}
