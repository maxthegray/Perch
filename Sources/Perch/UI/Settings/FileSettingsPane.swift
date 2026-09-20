import SwiftUI

/// What happens to files as they enter, change inside, and leave Perch.
struct FileSettingsPane: View {
    @AppStorage(PerchSettings.referenceDroppedFiles)
    private var referenceDroppedFiles = false
    @AppStorage(PerchSettings.offerRecentArrivals)
    private var offerRecentArrivals = true
    @AppStorage(PerchSettings.transformOutputMode)
    private var transformOutputMode = ShelfTransformOutputMode.duplicate
    @AppStorage(PerchSettings.vendCopies)
    private var vendCopies = false

    var body: some View {
        ZStack(alignment: .top) {
            FileFlowPath()
                .stroke(
                    Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 16) {
                stage(title: "Drag in", symbol: "arrow.down.to.line") {
                    dragInSettings
                }
                stage(title: "Perch", symbol: "bird", prominent: true) {
                    transformSettings
                }
                stage(title: "Drag out", symbol: "arrow.up.from.line") {
                    dragOutSettings
                }
            }
        }
        .padding(18)
    }

    private func stage<Content: View>(
        title: String,
        symbol: String,
        prominent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                    Circle()
                        .stroke(
                            Color.primary.opacity(prominent ? 0.16 : 0.1),
                            lineWidth: 0.5
                        )
                    Image(systemName: symbol)
                        .font(.system(size: prominent ? 15 : 13, weight: .medium))
                        .foregroundStyle(
                            prominent ? Color.primary : Color.secondary.opacity(0.85)
                        )
                }
                .frame(width: prominent ? 38 : 34, height: prominent ? 38 : 34)

                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(prominent ? 0.055 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(prominent ? 0.12 : 0.075), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var dragInSettings: some View {
        Group {
            settingHeading("Store dropped files")
            Picker("Store dropped files", selection: $referenceDroppedFiles) {
                Text("Inside Perch").tag(false)
                Text("In their original location").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .controlSize(.small)

            Text(referenceDroppedFiles
                ? "Files stay where they are."
                : "Files move into Perch's storage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Show recent arrivals", isOn: $offerRecentArrivals)
                .toggleStyle(.switch)
                .controlSize(.small)
            Text("Offer new files from Downloads and the Desktop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transformSettings: some View {
        Group {
            settingHeading("After transforming a file")
            Picker("After transforming a file", selection: $transformOutputMode) {
                Text("Keep the original").tag(ShelfTransformOutputMode.duplicate)
                Text("Replace the original").tag(ShelfTransformOutputMode.replace)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .controlSize(.small)

            Text(transformOutputMode == .duplicate
                ? "Add the result beside the source."
                : "Remove the source after the transform succeeds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dragOutSettings: some View {
        Group {
            settingHeading("After dragging a file out")
            Picker("After dragging a file out", selection: $vendCopies) {
                Text("Remove from Perch").tag(false)
                Text("Keep in Perch").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .controlSize(.small)

            Text(vendCopies
                ? "The item stays on the shelf."
                : "The item leaves the shelf. Hold Option to keep it once.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingHeading(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
    }
}

private struct FileFlowPath: Shape {
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.width / 6, y: 19)
        let end = CGPoint(x: rect.width * 5 / 6, y: 19)
        let control = CGPoint(x: rect.midX, y: -4)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        path.move(to: CGPoint(x: end.x - 8, y: end.y - 2))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 5, y: end.y + 7))
        return path
    }
}
