import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings

/// Central manager for Screen Time API interactions.
/// Called from Flutter via MethodChannel.
@available(iOS 16.0, *)
final class ScreenTimeManager {
    static let shared = ScreenTimeManager()
    
    private let center = AuthorizationCenter.shared
    private let activityCenter = DeviceActivityCenter()
    private let store = ManagedSettingsStore()
    private let sharedStore = SharedStore.shared
    
    // MARK: - Authorization
    
    /// Request Screen Time authorization (equivalent to Android's Usage Access + Overlay)
    func requestAuthorization() async throws {
        try await center.requestAuthorization(for: .individual)
    }
    
    /// Current authorization status
    var authorizationStatus: AuthorizationStatus {
        center.authorizationStatus
    }
    
    var isAuthorized: Bool {
        center.authorizationStatus == .approved
    }
    
    // MARK: - App Selection
    
    /// Save selected apps and update shield
    func saveSelection(_ selection: FamilyActivitySelection) {
        sharedStore.saveSelection(selection)
        
        // If monitoring is active, update shield immediately
        if sharedStore.isServiceEnabled {
            applyShield(selection: selection)
        }
    }
    
    func loadSelection() -> FamilyActivitySelection? {
        sharedStore.loadSelection()
    }
    
    var selectedAppCount: Int {
        sharedStore.loadSelection()?.applicationTokens.count ?? 0
    }
    
    // MARK: - Monitoring (Start / Stop)
    
    /// Start monitoring — applies shield to selected apps and starts DeviceActivity schedule
    func startMonitoring() throws {
        guard let selection = sharedStore.loadSelection(),
              !selection.applicationTokens.isEmpty else {
            return
        }
        
        // Apply shield overlay on selected apps
        applyShield(selection: selection)
        
        // Start a 24/7 DeviceActivity monitoring schedule
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        // Create events for threshold-based monitoring
        // We use a threshold of 0 seconds — triggers immediately when app is opened
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for token in selection.applicationTokens {
            let eventName = DeviceActivityEvent.Name(token.hashValue.description)
            events[eventName] = DeviceActivityEvent(
                applications: Set([token]),
                threshold: DateComponents(second: 1)
            )
        }
        
        let activityName = DeviceActivityName("mindful_pause_daily")
        
        // Stop previous monitoring if any
        activityCenter.stopMonitoring([activityName])
        
        try activityCenter.startMonitoring(
            activityName,
            during: schedule,
            events: events
        )
        
        sharedStore.isServiceEnabled = true
        sharedStore.isMonitoringActive = true
    }
    
    /// Stop monitoring — remove shields and stop DeviceActivity
    func stopMonitoring() {
        // Remove all shields
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        
        // Stop DeviceActivity monitoring
        activityCenter.stopMonitoring()
        
        sharedStore.isServiceEnabled = false
        sharedStore.isMonitoringActive = false
    }
    
    var isMonitoring: Bool {
        sharedStore.isMonitoringActive && sharedStore.isServiceEnabled
    }
    
    // MARK: - Shield Management
    
    /// Apply shield to selected applications
    private func applyShield(selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens
        
        if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
    }
    
    /// Temporarily remove shield for a specific app (after pause completed)
    func liftShield(for appTokenHash: String) {
        // Record confirmation
        sharedStore.confirmPause(appTokenHash: appTokenHash)
        
        // Temporarily remove ALL shields, then re-apply after cooldown
        // (Screen Time API doesn't allow per-app temporary unshield easily,
        //  so we remove and schedule re-apply)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        
        let cooldownSeconds = sharedStore.isCooldownEnabled
            ? Double(sharedStore.cooldownMinutes) * 60.0
            : 5.0  // Minimum 5 seconds to allow app to open
        
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldownSeconds) { [weak self] in
            self?.reapplyShieldIfNeeded()
        }
    }
    
    /// Re-apply shield after cooldown expires
    func reapplyShieldIfNeeded() {
        guard sharedStore.isServiceEnabled,
              let selection = sharedStore.loadSelection(),
              !selection.applicationTokens.isEmpty else {
            return
        }
        applyShield(selection: selection)
    }
    
    // MARK: - Cooldown
    
    func setCooldownMinutes(_ minutes: Int) {
        sharedStore.cooldownMinutes = minutes
    }
    
    func setCooldownEnabled(_ enabled: Bool) {
        sharedStore.isCooldownEnabled = enabled
    }
    
    // MARK: - Cleanup
    
    func clearAllData() {
        stopMonitoring()
        sharedStore.clearAllData()
    }
}