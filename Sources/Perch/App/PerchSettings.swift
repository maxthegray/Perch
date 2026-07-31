import Foundation

/// Every `UserDefaults` key Perch writes, in one place.
///
/// Keys used to live on whichever type happened to read them, which meant the controller
/// reached into a *view* (`ShelfHostView.shakeToSummonKey`) for a flag the view never
/// touched, and the same string could be spelled twice in two files. Declaring them here
/// keeps the settings tiers legible — General, Advanced, Smart Perch — and makes a
/// collision or typo a compile error rather than a silently separate preference.
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
    /// Set the first time a ⌘-drag actually moves the card. Retires the menu footnote
    /// that teaches the gesture — it has a job, and once it is done it should stop.
    static let moveHintRetired = "Perch.MoveHintRetired"
    /// The last version whose What's New window was shown (or skipped, on a new install).
    /// Anything newer than this on launch is an update the user has not been told about.
    static let lastSeenVersion = "Perch.LastSeenVersion"

    // MARK: - Advanced ▸ Appearance

    static let shelfStyle = "Perch.ShelfStyle"
    static let showsLabels = "Perch.ShowsLabels"
    static let showsGrabHandle = "Perch.ShowsGrabHandle"
    static let showsShadow = "Perch.ShowsShadow"
    static let showsEdgeTab = "Perch.ShowsEdgeTab"
    static let sizePreset = "Perch.SizePreset"
    static let stacksItems = "Perch.StacksItems"
    /// Retired in favour of `sizePreset`. The two slider values are read once to place an
    /// upgrading install on the nearest preset, then never written again — left on disk so
    /// a downgrade still finds the size the user had.
    static let widthScale = "Perch.WidthScale"
    static let heightFraction = "Perch.HeightFraction"
    /// Retired outright. It only ever disambiguated the Square preset from the slider
    /// values that produced it, and those values now land on `wide` without help.
    static let squarePresetSelected = "Perch.SquarePresetSelected"

    // MARK: - Advanced ▸ Behavior

    /// Reveal the shelf at the nearest enabled edge the moment a drag starts, instead of
    /// waiting for the pointer to reach the edge tab. Defaults on.
    static let revealOnDragStart = "Perch.RevealOnDragStart"
    /// Reveal the shelf when the pointer rests at an enabled edge. Defaults on, matching
    /// the behavior that had no switch — off leaves the edges inert until a drag.
    static let revealOnHover = "Perch.RevealOnHover"
    /// Shaking the cursor summons a free-floating shelf at the pointer. Defaults on,
    /// matching the original always-on behavior.
    static let shakeToSummon = "Perch.ShakeToSummon"
    /// A free-floating shelf stays put (as the empty drop tile) after its last item
    /// leaves, instead of dismissing itself. Defaults on.
    static let keepEmptyShelf = "Perch.KeepEmptyShelf"
    /// Offer recently downloaded files as ghost rows.
    static let offerRecentArrivals = "Perch.OfferRecentArrivals"

    // MARK: - Advanced ▸ Docking

    static let snapBesideDock = "Perch.SnapBesideDock"

    // MARK: - Smart Perch

    /// Master switch for Smart Perch. Off means the feature is never built: no database,
    /// no OCR, nothing recorded.
    static let smartPerchEnabled = "Perch.SmartPerchEnabled"
    /// Whether the Smart Perch pane is visible. Off until the user asks for it.
    static let smartPerchUnlocked = "Perch.LabsUnlocked"

    // MARK: - Internal state (not user-facing)

    static let smartPerchAutoEnabledNames = "Perch.SmartPerchAutoEnabledNames"
    /// Set once the welcome window has been shown and answered — or, for an install that
    /// predates it, once that install has been recognized as an upgrade. See
    /// `FirstRunExperience`.
    static let firstRunCompleted = "Perch.FirstRunCompleted"
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
