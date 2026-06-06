import AppKit

// T0.1: build the NSApplication, run as an accessory (no Dock icon / menu bar), and run.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
