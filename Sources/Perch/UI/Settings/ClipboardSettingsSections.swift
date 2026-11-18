import AppKit
import SwiftUI

struct ClipboardSettingsSections: View {
    @ObservedObject var clipboard: ClipboardCoordinator
    let onShowData: () -> Void

    @State private var showsClearConfirmation = false
    @AppStorage(PerchSettings.clipboardStyle) private var style = ClipboardStyle.defaultStyle

    var body: some View {
        Group {
            Section {
                Toggle(isOn: enabledBinding) {
                    Text("Perch Clipboard")
                    Text(caption)
                }

                Picker("Look", selection: $style) {
                    ForEach(ClipboardStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!clipboard.isEnabled)

                LabeledContent("Shortcut") {
                    HotKeyRecorder(clipboard: clipboard)
                }
                .disabled(!clipboard.isEnabled)
            } footer: {
                Text("↩ copy   ⌘1–9 pick   ⌥⌫ delete   esc close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("See Collected Data…", action: onShowData)
                    Button("Clear History…") { showsClearConfirmation = true }
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
        .alert("Clear Perch Clipboard’s history?", isPresented: $showsClearConfirmation) {
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
            .frame(minWidth: 110, alignment: .trailing)
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
