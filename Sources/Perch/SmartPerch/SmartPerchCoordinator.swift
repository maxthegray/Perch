import Foundation
import SmartPerchCore
import SmartPerchVision

@MainActor
final class SmartPerchCoordinator: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isRemoving = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var errorMessage: String?

    let smartNames = SmartNameStore()
    let routeSuggestions = RouteSuggestionStore()

    var onPresentationChanged: (() -> Void)?
    var onActivityChanged: ((Bool) -> Void)?

    private let databaseURL: URL
    private let arrivals: RecentArrivals
    private let store: ItemStore
    private let themeStore: ThemeStore
    private var feature: SmartPerchFeature?
    private var shutdownTasks: [UUID: Task<Void, Never>] = [:]

    init(
        databaseURL: URL,
        arrivals: RecentArrivals,
        store: ItemStore,
        themeStore: ThemeStore
    ) {
        self.databaseURL = databaseURL
        self.arrivals = arrivals
        self.store = store
        self.themeStore = themeStore
    }

    func bootstrap() {
        guard SmartPerchSettings.isEnabled else {
            setPresentationEnabled(false)
            return
        }
        SmartPerchAccess.unlock()
        activate(loadExistingState: false)
    }

    func loadExistingState() {
        feature?.registerStoredScreenshotPresentations()
        feature?.loadFilenameSuggestions()
        feature?.refreshRouteSuggestions()
        feature?.prepareArrivalSmartNames()
    }

    func setEnabled(_ enabled: Bool) {
        guard !isRemoving, !isTransitioning, enabled != isEnabled else { return }
        errorMessage = nil

        let showsNames = themeStore.showsLabels
        themeStore.showsLabels = SmartPerchNamePreference.settingAfterSmartPerchChange(
            enabled: enabled,
            currentlyShowsNames: showsNames
        )
        UserDefaults.standard.set(enabled, forKey: PerchSettings.smartPerchEnabled)

        if enabled {
            SmartPerchAccess.unlock()
            activate(loadExistingState: true)
        } else {
            beginDeactivation()
        }
    }

    func removeData() async -> Bool {
        guard !isRemoving else { return false }
        isRemoving = true
        errorMessage = nil

        if isEnabled {
            let showsNames = themeStore.showsLabels
            themeStore.showsLabels = SmartPerchNamePreference.settingAfterSmartPerchChange(
                enabled: false,
                currentlyShowsNames: showsNames
            )
        }
        UserDefaults.standard.set(false, forKey: PerchSettings.smartPerchEnabled)
        let activeFeature = deactivate()
        SmartPerchDataRemoval.markPending()

        if let activeFeature {
            await activeFeature.shutDown()
        }
        let pendingShutdowns = Array(shutdownTasks.values)
        shutdownTasks.removeAll()
        for task in pendingShutdowns {
            await task.value
        }

        do {
            try SmartPerchDataRemoval.removeNow(databaseURL: databaseURL)
            SmartPerchDataRemoval.finishPreferences()
            isRemoving = false
            isTransitioning = false
            return true
        } catch {
            errorMessage = "Smart Perch is off, but its saved data could not be deleted."
            isRemoving = false
            isTransitioning = false
            return false
        }
    }

    private func activate(loadExistingState: Bool) {
        guard feature == nil else { return }
        setPresentationEnabled(true)

        guard let newFeature = SmartPerchFeature(
            databaseURL: databaseURL,
            smartNames: smartNames,
            routeSuggestions: routeSuggestions,
            arrivals: arrivals,
            currentItems: { [store] in store.items }
        ) else {
            UserDefaults.standard.set(false, forKey: PerchSettings.smartPerchEnabled)
            themeStore.showsLabels = SmartPerchNamePreference.settingAfterSmartPerchChange(
                enabled: false,
                currentlyShowsNames: themeStore.showsLabels
            )
            setPresentationEnabled(false)
            errorMessage = "Smart Perch could not open its local database."
            return
        }

        feature = newFeature
        isEnabled = true
        onActivityChanged?(true)
        if loadExistingState {
            self.loadExistingState()
        }
    }

    private func beginDeactivation() {
        guard let oldFeature = deactivate() else { return }
        let id = UUID()
        isTransitioning = true
        shutdownTasks[id] = Task { @MainActor [weak self] in
            await oldFeature.shutDown()
            guard let self else { return }
            self.shutdownTasks[id] = nil
            if self.shutdownTasks.isEmpty && !self.isRemoving {
                self.isTransitioning = false
            }
        }
    }

    private func deactivate() -> SmartPerchFeature? {
        let oldFeature = feature
        feature = nil
        isEnabled = false
        setPresentationEnabled(false)
        smartNames.reset()
        routeSuggestions.replace(with: [:])
        arrivals.clearSmartNames()
        onActivityChanged?(false)
        onPresentationChanged?()
        return oldFeature
    }

    private func setPresentationEnabled(_ enabled: Bool) {
        let changed = smartNames.isEnabled != enabled || routeSuggestions.isEnabled != enabled
        smartNames.isEnabled = enabled
        routeSuggestions.isEnabled = enabled
        if changed {
            onPresentationChanged?()
        }
    }

    func recordSuccessfulRoutes(_ routes: [ItemRouteEvent]) {
        feature?.recordSuccessfulRoutes(routes)
    }

    func prepareArrivalSmartNames() {
        feature?.prepareArrivalSmartNames()
    }

    func takeArrivalAnalysis(
        forPath path: String,
        adoptingAs itemID: UUID
    ) -> ScreenshotOCRResult? {
        feature?.takeArrivalAnalysis(forPath: path, adoptingAs: itemID)
    }

    func recordArrivalSessionInteraction(
        _ session: ArrivalSession,
        action: ArrivalSessionAction,
        affectedFileCount: Int
    ) {
        feature?.recordArrivalSessionInteraction(
            session,
            action: action,
            affectedFileCount: affectedFileCount
        )
    }

    func plannedRename(
        of item: StoredItem,
        to proposedFilename: String
    ) -> SmartPerchFeature.AcceptedRename? {
        feature?.plannedRename(of: item, to: proposedFilename)
    }

    func didAcceptRename(
        _ rename: SmartPerchFeature.AcceptedRename,
        acceptedFilename: String
    ) {
        feature?.didAcceptRename(rename, acceptedFilename: acceptedFilename)
    }

    func dismissFilenameSuggestion(for item: StoredItem) {
        feature?.dismissFilenameSuggestion(for: item)
    }

    func handleDerivedOutput(
        action: ShelfTransformAction,
        sources: [StoredItem],
        output: StoredItem
    ) {
        feature?.handleDerivedOutput(
            action: action,
            sources: sources,
            output: output
        )
    }

    func beginFilingAtSuggestedRoute(
        _ item: StoredItem
    ) -> SmartPerchFeature.RouteFiling? {
        feature?.beginFilingAtSuggestedRoute(item)
    }

    func abandonFiling(_ filing: SmartPerchFeature.RouteFiling) {
        feature?.abandonFiling(filing)
    }

    func didFileAtSuggestedRoute(_ filing: SmartPerchFeature.RouteFiling) {
        feature?.didFileAtSuggestedRoute(filing)
    }

    func itemsDidChange(_ items: [StoredItem], countChanged: Bool) {
        feature?.itemsDidChange(items, countChanged: countChanged)
    }

    func recordDrop(
        _ item: StoredItem,
        context: DropRecordingContext,
        payloadKind: DropPayloadKind,
        screenshotCaptureContexts: [ScreenshotCaptureContext?]? = nil,
        prefetchedOCRResults: [ScreenshotOCRResult?]? = nil
    ) {
        feature?.recordDrop(
            item,
            context: context,
            payloadKind: payloadKind,
            screenshotCaptureContexts: screenshotCaptureContexts,
            prefetchedOCRResults: prefetchedOCRResults
        )
    }

    @discardableResult
    func registerScreenshotPresentationIfNeeded(for item: StoredItem) -> Bool {
        feature?.registerScreenshotPresentationIfNeeded(for: item) ?? false
    }
}
