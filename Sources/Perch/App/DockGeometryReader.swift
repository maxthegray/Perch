import AppKit
import ApplicationServices

/// Reads the Dock's live bounds for the optional "Beside Dock" snap targets.
/// macOS only exposes the Dock's exact, item-dependent length through Accessibility;
/// callers get no geometry unless the user explicitly enabled the feature and granted
/// Perch access. Permission is requested only from the Settings toggle.
@MainActor
enum DockGeometryReader {
    static let enabledKey = "Perch.SnapBesideDock"

    struct Geometry {
        enum Orientation { case horizontal, vertical }

        let frame: NSRect
        let screen: NSScreen
        let orientation: Orientation
    }

    private static var promptedThisRun = false
    private static var cachedGeometry: Geometry?
    private static var cacheDate = Date.distantPast

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask macOS to show its standard Accessibility explanation and Settings shortcut.
    /// The in-process guard prevents repeated alerts if the toggle is clicked more than
    /// once; subsequent launches only check trust silently.
    static func requestPermissionIfNeeded() {
        guard !isTrusted, !promptedThisRun else { return }
        promptedThisRun = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func currentGeometry(
        useCache: Bool = true,
        requireFeatureEnabled: Bool = true
    ) -> Geometry? {
        guard (!requireFeatureEnabled || UserDefaults.standard.bool(forKey: enabledKey)),
              isTrusted
        else { return nil }
        if useCache, Date().timeIntervalSince(cacheDate) < 0.5 {
            return cachedGeometry
        }
        cacheDate = Date()
        cachedGeometry = readGeometry()
        return cachedGeometry
    }

    private static func readGeometry() -> Geometry? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return nil }

        let application = AXUIElementCreateApplication(dock.processIdentifier)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement]
        else { return nil }

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        for child in children {
            guard let accessibilityFrame = rectAttribute("AXFrame", of: child),
                  accessibilityFrame.width > 0,
                  accessibilityFrame.height > 0
            else { continue }

            // Accessibility uses a top-left global origin; AppKit screen coordinates
            // use bottom-left. The primary display's top edge is the shared baseline.
            let frame = NSRect(
                x: accessibilityFrame.minX,
                y: primaryTop - accessibilityFrame.minY - accessibilityFrame.height,
                width: accessibilityFrame.width,
                height: accessibilityFrame.height
            )
            let orientation: Geometry.Orientation = frame.width >= frame.height
                ? .horizontal
                : .vertical
            guard min(frame.width, frame.height) < 300,
                  let screen = screen(containingDockFrame: frame, orientation: orientation)
            else { continue }
            return Geometry(frame: frame, screen: screen, orientation: orientation)
        }
        return nil
    }

    private static func screen(
        containingDockFrame frame: NSRect,
        orientation: Geometry.Orientation
    ) -> NSScreen? {
        switch orientation {
        case .horizontal:
            return NSScreen.screens.first { frame.midX >= $0.frame.minX && frame.midX <= $0.frame.maxX }
        case .vertical:
            return NSScreen.screens.first { frame.midY >= $0.frame.minY && frame.midY <= $0.frame.maxY }
        }
    }

    private static func rectAttribute(_ attribute: String, of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
    }
}
