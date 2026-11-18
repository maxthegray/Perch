import AppKit

/// Quits Perch and opens it again once this process has fully exited.
enum Relauncher {
    static func restart() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            NSLog("Perch could not schedule a relaunch: \(error)")
            return
        }
        NSApp.terminate(nil)
    }
}
