import AppKit
import SwiftUI

struct ClipboardSettingsSections: View {
    @ObservedObject var clipboard: ClipboardCoordinator
    let onShowData: () -> Void

    @State private var showsClearConfirmation = false
    @AppStorage(PerchSettings.clipboardStyle) private var style = MagpieStyle.defaultStyle

    var body: some View {
        Group {
            Section {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Magpie")
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Magpie", isOn: enabledBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)

                Picker("Look", selection: $style) {
                    ForEach(MagpieStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!clipboard.isEnabled)

                LabeledContent("Shortcut") {
                    HotKeyRecorder(clipboard: clipboard)
                }
                .disabled(!clipboard.isEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button("See Collected Data…", action: onShowData)
                        Button("Clear History…") { showsClearConfirmation = true }
                    }
                    Text("↩ copy   ⌘1–9 pick   ⌥⌫ delete   esc close")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = clipboard.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .alert("Clear Magpie’s history?", isPresented: $showsClearConfirmation) {
            Button("Clear History", role: .destructive) { clipboard.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Can’t be undone")
        }
    }

    private var caption: String {
        clipboard.isEnabled
            ? "\(clipboard.hotKey.displayString) to open"
            : "Off"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { clipboard.isEnabled }, set: { clipboard.setEnabled($0) })
    }
}

/// Click, then press the new shortcut. Esc cancels.
struct HotKeyRecorder: View {
    @ObservedObject var clipboard: ClipboardCoordinator

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? "Type shortcut…" : clipboard.hotKey.displayString) {
                isRecording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 110)
            if clipboard.hotKey != .clipboardDefault, !isRecording {
                Button("Reset") { clipboard.setHotKey(.clipboardDefault) }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        clipboard.suspendHotKey()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
            } else if let combo = KeyCombo(event: event) {
                stopRecording(saving: combo)
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        stopRecording(saving: nil)
    }

    private func stopRecording(saving combo: KeyCombo?) {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        if let combo {
            clipboard.setHotKey(combo)
        } else {
            clipboard.resumeHotKey()
        }
    }
}
