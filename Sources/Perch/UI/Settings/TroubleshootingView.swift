import AppKit
import SwiftUI

/// The troubleshooting sheet: every check with its status, a fix where one exists, and
/// a plain-text report to send to Max.
struct TroubleshootingView: View {
    @ObservedObject var clipboard: ClipboardCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var checks: [DiagnosticCheck] = []
    @State private var errors: [String] = []
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(checks) { check in
                        row(check)
                    }
                } header: {
                    Text(summary)
                }

                Section("Recent errors") {
                    if errors.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(errors.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(copied ? "Copied" : "Copy Report", action: copyReport)
                Spacer()
                Button("Check Again", action: refresh)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .task { refresh() }
    }

    private var summary: String {
        let problems = checks.filter { $0.status == .problem }.count
        switch problems {
        case 0: return "No problems found"
        case 1: return "1 problem found"
        default: return "\(problems) problems found"
        }
    }

    private func row(_ check: DiagnosticCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol(for: check.status))
                .foregroundStyle(color(for: check.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let fix = check.fix {
                Button(fix.title) {
                    fix.perform()
                    refresh()
                }
            }
        }
    }

    private func symbol(for status: DiagnosticCheck.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        case .note: return "info.circle.fill"
        }
    }

    private func color(for status: DiagnosticCheck.Status) -> Color {
        switch status {
        case .ok: return .green
        case .problem: return .orange
        case .note: return .secondary
        }
    }

    private func refresh() {
        copied = false
        checks = Diagnostics.run(clipboard: clipboard)
        errors = Diagnostics.recentErrors()
    }

    private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Diagnostics.report(checks: checks, errors: errors), forType: .string)
        copied = true
    }
}
