import Foundation

/// Every `UserDefaults` key Perch writes, in one place.
///
/// Keys used to live on whichever type happened to read them, which meant the controller
/// reached into a *view* (`ShelfHostView.shakeToSummonKey`) for a flag the view never
/// touched, and the same string could be spelled twice in two files. Declaring them here
/// keeps the settings tiers legible — General, Advanced, Labs — and makes a collision or a
/// typo a compile error rather than a silently separate preference.
///
/// The string values are load-bearing: they are what is already on disk in every install.
/// Renaming a constant is free; changing its value silently resets that preference.
enum PerchSettings {
    // MARK: - General

    /// When true, dragging an item out leaves the original on the shelf (copy); otherwise
    /// it is removed once it lands somewhere (move — the default).
    static let vendCopies = "Perch.VendCopies"
    /// Raw values of the edges the shelf is allowed to dock to.
    static let enabledEdges = "Perch.EnabledEdges"

    // MARK: - Advanced ▸ Appearance

    static let shelfStyle = "Perch.ShelfStyle"
    static let showsLabels = "Perch.ShowsLabels"
    static let showsGrabHandle = "Perch.ShowsGrabHandle"
    static let showsShadow = "Perch.ShowsShadow"
    static let showsEdgeTab = "Perch.ShowsEdgeTab"
    static let widthScale = "Perch.WidthScale"
    static let heightFraction = "Perch.HeightFraction"
    static let stacksItems = "Perch.StacksItems"
    static let squarePresetSelected = "Perch.SquarePresetSelected"

    // MARK: - Advanced ▸ Behavior

    /// Reveal the shelf at the nearest enabled edge the moment a drag starts, instead of
    /// waiting for the pointer to reach the edge tab. Defaults on.
    static let revealOnDragStart = "Perch.RevealOnDragStart"
    /// Shaking the cursor summons a free-floating shelf at the pointer. Defaults on,
    /// matching the original always-on behavior.
    static let shakeToSummon = "Perch.ShakeToSummon"
    /// A free-floating shelf stays put (as the empty drop tile) after its last item
    /// leaves, instead of dismissing itself. Defaults on.
    static let keepEmptyShelf = "Perch.KeepEmptyShelf"
    /// Releasing a free shelf near an enabled dock previews the target and snaps it back
    /// into ordinary edge behavior. Defaults on.
    static let snapBackToEdges = "Perch.SnapBackToEdges"
    /// Offer recently downloaded files as ghost rows.
    static let offerRecentArrivals = "Perch.OfferRecentArrivals"

    // MARK: - Advanced ▸ Docking

    static let snapBesideDock = "Perch.SnapBesideDock"

    // MARK: - Labs

    /// Master switch for Smart Perch. Off means the feature is never built: no database,
    /// no OCR, nothing recorded.
    static let smartPerchEnabled = "Perch.SmartPerchEnabled"
    /// Whether Smart Perch displays what it has learned. Only meaningful while the master
    /// switch is on; off means it keeps learning with nothing on screen.
    static let smartPerchShowsSuggestions = "Perch.SmartPerchShowsSuggestions"

    // MARK: - Internal state (not user-facing)

    /// The edge the shelf considers home between launches.
    static let preferredShelfEdge = "Perch.PreferredShelfEdge"
    static let arrivalDismissed = "Perch.ArrivalDismissed"
    static let arrivalRevealCounts = "Perch.ArrivalRevealCounts"
    static let launchAtLoginDefaultApplied = "Perch.LaunchAtLoginDefaultApplied"
    static let launchAtLoginUserChoice = "Perch.LaunchAtLoginUserChoice"

    // MARK: - Reading

    /// Reads a flag that is on unless the user turned it off.
    ///
    /// Most of Perch's switches ship enabled, so an *absent* value has to read as `true` —
    /// `UserDefaults.bool(forKey:)` returns `false` for a missing key and would silently
    /// disable the feature for every install that had never opened Settings.
    static func flag(_ key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
