import Foundation
import ManagedSettings
import FamilyControls
import DeviceActivity

// MARK: - App Group

/// App Group identifier — must match in all targets' entitlements
let kAppGroupID = "group.com.example.mindfull"

// MARK: - UserDefaults Keys

enum SharedKey {
    static let serviceEnabled      = "service_enabled"
    static let cooldownMinutes     = "cooldown_minutes"
    static let cooldownEnabled     = "cooldown_enabled"
    static let selectionData       = "family_activity_selection"
    static let cooldownTimestamps  = "cooldown_timestamps"  // [String: TimeInterval]
    static let pauseConfirmedApp   = "pause_confirmed_app"
    static let pauseConfirmedAt    = "pause_confirmed_at"
    static let monitoringActive    = "monitoring_active"
}

// MARK: - Shared UserDefaults Accessor

/// Thread-safe accessor for App Group UserDefaults.
/// Used by the main app AND all three extensions.
final class SharedStore {
    static let shared = SharedStore()
    
    let defaults: UserDefaults
    
    private init() {
        guard let d = UserDefaults(suiteName: kAppGroupID) else {
            fatalError("App Group '\(kAppGroupID)' not configured. Add it to all targets.")
        }
        self.defaults = d
    }
    
    // MARK: Service state
    
    var isServiceEnabled: Bool {
        get { defaults.bool(forKey: SharedKey.serviceEnabled) }
        set { defaults.set(newValue, forKey: SharedKey.serviceEnabled) }
    }
    
    var isMonitoringActive: Bool {
        get { defaults.bool(forKey: SharedKey.monitoringActive) }
        set { defaults.set(newValue, forKey: SharedKey.monitoringActive) }
    }
    
    // MARK: Cooldown
    
    var cooldownMinutes: Int {
        get {
            let v = defaults.integer(forKey: SharedKey.cooldownMinutes)
            return v > 0 ? v : 5
        }
        set { defaults.set(newValue, forKey: SharedKey.cooldownMinutes) }
    }
    
    var isCooldownEnabled: Bool {
        get {
            // Default to true if never set
            if defaults.object(forKey: SharedKey.cooldownEnabled) == nil { return true }
            return defaults.bool(forKey: SharedKey.cooldownEnabled)
        }
        set { defaults.set(newValue, forKey: SharedKey.cooldownEnabled) }
    }
    
    /// Per-app cooldown timestamps: [tokenHash: epochSeconds]
    var cooldownTimestamps: [String: TimeInterval] {
        get {
            defaults.dictionary(forKey: SharedKey.cooldownTimestamps) as? [String: TimeInterval] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: SharedKey.cooldownTimestamps)
        }
    }
    
    func setCooldownTimestamp(for tokenHash: String) {
        var ts = cooldownTimestamps
        ts[tokenHash] = Date().timeIntervalSince1970
        cooldownTimestamps = ts
    }
    
    func isInCooldown(for tokenHash: String) -> Bool {
        guard isCooldownEnabled else { return false }
        guard let lastConfirm = cooldownTimestamps[tokenHash] else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastConfirm
        let cooldownSeconds = Double(cooldownMinutes) * 60.0
        return elapsed < cooldownSeconds
    }
    
    // MARK: FamilyActivitySelection persistence
    
    func saveSelection(_ selection: FamilyActivitySelection) {
        let encoder = PropertyListEncoder()
        if let data = try? encoder.encode(selection) {
            defaults.set(data, forKey: SharedKey.selectionData)
        }
    }
    
    func loadSelection() -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: SharedKey.selectionData) else { return nil }
        let decoder = PropertyListDecoder()
        return try? decoder.decode(FamilyActivitySelection.self, from: data)
    }
    
    func clearSelection() {
        defaults.removeObject(forKey: SharedKey.selectionData)
    }
    
    // MARK: Pause confirmation (for shield → app communication)
    
    func confirmPause(appTokenHash: String) {
        defaults.set(appTokenHash, forKey: SharedKey.pauseConfirmedApp)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKey.pauseConfirmedAt)
        
        if isCooldownEnabled {
            setCooldownTimestamp(for: appTokenHash)
        }
    }
    
    func consumePauseConfirmation() -> String? {
        guard let app = defaults.string(forKey: SharedKey.pauseConfirmedApp) else { return nil }
        let at = defaults.double(forKey: SharedKey.pauseConfirmedAt)
        let elapsed = Date().timeIntervalSince1970 - at
        
        // Expire after 30 seconds
        defaults.removeObject(forKey: SharedKey.pauseConfirmedApp)
        defaults.removeObject(forKey: SharedKey.pauseConfirmedAt)
        
        return elapsed < 30 ? app : nil
    }
    
    // MARK: Reset
    
    func clearAllData() {
        let keys = [
            SharedKey.serviceEnabled,
            SharedKey.cooldownMinutes,
            SharedKey.cooldownEnabled,
            SharedKey.selectionData,
            SharedKey.cooldownTimestamps,
            SharedKey.pauseConfirmedApp,
            SharedKey.pauseConfirmedAt,
            SharedKey.monitoringActive,
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}