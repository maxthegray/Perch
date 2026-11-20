import AppKit
import SwiftUI

/// The troubleshooting sheet: raw status lines, a fix button where one exists, the
/// recent failure log, and the same text copyable as a report.
struct TroubleshootingView: View {
    @ObservedObject var clipboard: ClipboardCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var checks: [DiagnosticCheck] = []
    @State private var errors: [String] = []
    @State private var arrivals: [String] = []
    @State private var copied = false

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary)
                        .font(mono.weight(.semibold))

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(checks) { check in
                            GridRow {
                                Text(Diagnostics.mark(for: check.status))
                                    .foregroundStyle(color(for: check.status))
                                Text(check.title)
                                Text(check.detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let fix = check.fix {
                                    Button(fix.title) {
                                        fix.perform()
                                        refresh()
                                    }
                                    .controlSize(.small)
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }

                    Divider()

                    Text("log (\(errors.count))")
                        .font(mono.weight(.semibold))
                    Text(errors.isEmpty ? "none" : errors.joined(separator: "\n"))
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("arrivals (\(arrivals.count))")
                        .font(mono.weight(.semibold))
                    Text(arrivals.isEmpty ? "none" : arrivals.joined(separator: "\n"))
                        .foregroundStyle(.secondary)
                }
                .font(mono)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Button(copied ? "Copied" : "Copy", action: copyReport)
                Button("Rerun", action: refresh)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: 640, height: 420)
        .task { refresh() }
    }

    private var summary: String {
        let fail = checks.filter { $0.status == .problem }.count
        let ok = checks.filter { $0.status == .ok }.count
        return "\(fail) fail  \(ok) ok  \(checks.count - fail - ok) info"
    }

    private func color(for status: DiagnosticCheck.Status) -> Color {
        switch status {
        case .ok: return .green
        case .problem: return .red
        case .note: return .secondary
        }
    }

    private func refresh() {
        copied = false
        checks = Diagnostics.run(clipboard: clipboard)
        errors = Diagnostics.recentErrors()
        arrivals = Diagnostics.recentArrivals()
    }

    private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Diagnostics.report(checks: checks, errors: errors, arrivals: arrivals), forType: .string)
        copied = true
    }
}
