import DeviceActivity
import ManagedSettings
import Foundation

/// Extension that responds to DeviceActivity events.
/// Runs in a separate process — cannot access main app's memory.
/// Communicates via App Group UserDefaults (SharedStore).
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    let store = ManagedSettingsStore()
    let sharedStore = SharedStore.shared
    
    // Called when a monitoring interval starts (daily at 00:00)
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        
        // Re-apply shields at the start of each day
        reapplyShields()
    }
    
    // Called when a monitoring interval ends (daily at 23:59)
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        
        // Re-apply shields for the next interval
        reapplyShields()
    }
    
    // Called when an app usage event reaches its threshold
    // This is the iOS equivalent of detecting "app launched"
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        // The shield is already applied via ManagedSettingsStore,
        // so the user sees it automatically.
        // We can use this callback for analytics or logging if needed.
    }
    
    // Called when device activity warning is triggered
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        // Not used — our interval repeats daily
    }
    
    // MARK: - Shield Management
    
    private func reapplyShields() {
        guard sharedStore.isServiceEnabled else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            return
        }
        
        guard let selection = sharedStore.loadSelection() else { return }
        
        if !selection.applicationTokens.isEmpty {
            store.shield.applications = selection.applicationTokens
        }
        
        if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
    }
}