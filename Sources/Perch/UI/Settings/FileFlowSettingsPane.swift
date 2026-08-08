import SwiftUI

struct FileFlowSettingsPane: View {
    @AppStorage(PerchSettings.referenceDroppedFiles)
    private var referenceDroppedFiles = false
    @AppStorage(PerchSettings.revealOnDragStart)
    private var revealOnDragStart = true
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

            HStack(alignment: .top, spacing: 20) {
                stage(title: "Drag In", symbol: "arrow.down.to.line") {
                    settingLabel("Dropped files")
                    Picker("Dropped files", selection: $referenceDroppedFiles) {
                        Text("Keep in Place").tag(true)
                        Text("Move to Perch").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    Toggle("Show while dragging", isOn: $revealOnDragStart)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .padding(.top, 6)

                    Toggle("Recent downloads", isOn: $offerRecentArrivals)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.top, 22)

                stage(title: "Perch", symbol: "bird", prominent: true) {
                    settingLabel("Transform output")
                    Picker("Transform output", selection: $transformOutputMode) {
                        ForEach(ShelfTransformOutputMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }

                stage(title: "Destination", symbol: "folder") {
                    settingLabel("Drag out")
                    Picker("Drag out", selection: $vendCopies) {
                        Text("Move").tag(false)
                        Text("Copy").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .padding(.top, 22)
            }
        }
        .frame(height: 215)
        .padding(22)
    }

    private func stage<Content: View>(
        title: String,
        symbol: String,
        prominent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                Circle()
                    .stroke(Color.primary.opacity(prominent ? 0.16 : 0.1), lineWidth: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 15 : 13, weight: .medium))
                    .foregroundStyle(prominent ? Color.primary : Color.secondary.opacity(0.85))
            }
            .frame(width: prominent ? 38 : 34, height: prominent ? 38 : 34)

            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.top, 5)

            VStack(spacing: 6) {
                content()
            }
            .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
    }

    private func settingLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}

private struct FileFlowPath: Shape {
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.width / 6, y: 39)
        let end = CGPoint(x: rect.width * 5 / 6, y: 39)
        let control = CGPoint(x: rect.midX, y: -1)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        path.move(to: CGPoint(x: end.x - 8, y: end.y - 2))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 5, y: end.y + 7))
        return path
    }
}
