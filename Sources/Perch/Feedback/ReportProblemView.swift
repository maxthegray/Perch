import SwiftUI

/// Help ▸ Report a Problem: say what happened, optionally attach the troubleshooting
/// report (shown in full before sending), and send it without leaving Perch.
struct ReportProblemView: View {
    let form: ProblemReportForm
    let makeReport: @MainActor () -> String
    let close: () -> Void

    private enum Phase: Equatable {
        case editing, sending, sent, failed
    }

    @State private var whatHappened = ""
    @State private var includesReport = true
    @State private var showsReport = false
    @State private var report = ""
    @State private var phase = Phase.editing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happened?")
                .font(.headline)
            TextEditor(text: $whatHappened)
                .font(.body)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .disabled(phase == .sending || phase == .sent)

            HStack {
                Toggle("Include troubleshooting report", isOn: $includesReport)
                Spacer()
                Button(showsReport ? "Hide" : "Show") { showsReport.toggle() }
                    .disabled(!includesReport)
            }
            Text("Versions, settings, recent logs and the names of recent files in Downloads and on the Desktop. No file contents or clipboard history.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsReport, includesReport {
                ScrollView {
                    Text(report)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                status
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                    .disabled(phase == .sending)
                Button(phase == .failed ? "Try Again" : "Send", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSend)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { report = makeReport() }
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .editing:
            EmptyView()
        case .sending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Sending").foregroundStyle(.secondary)
            }
        case .sent:
            Label("Sent. Thanks.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Text("Couldn't send. Check your connection.")
                .foregroundStyle(.red)
        }
    }

    private var canSend: Bool {
        guard phase == .editing || phase == .failed else { return false }
        return !whatHappened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || includesReport
    }

    private func send() {
        phase = .sending
        let text = whatHappened
        let attached = includesReport ? makeReport() : ""
        let version = ProblemReport.versionLine
        Task {
            do {
                try await form.submit(whatHappened: text, report: attached, version: version)
                NSLog("Perch sent a problem report")
                phase = .sent
                try? await Task.sleep(for: .seconds(1.2))
                close()
            } catch {
                NSLog("Perch could not send a problem report: \(error)")
                phase = .failed
            }
        }
    }
}

enum ProblemReport {
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Perch \(version) (\(build)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}
