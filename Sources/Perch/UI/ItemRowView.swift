import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI view for a single stored item (icon + title + kind).
struct ItemRowView: View {
    let item: StoredItem

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: item.iconImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.metadata.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .contentShape(Rectangle())
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
