import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Handles button taps on the shield overlay.
/// Primary button → opens main app for breathing pause
/// Secondary button → closes the blocked app (goes to home screen)
class ShieldActionExtension: ShieldActionDelegate {
    
    let sharedStore = SharedStore.shared
    
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // "Start pause" button — open the main app's pause screen
            // Store which app triggered the pause so Flutter knows
            let tokenHash = application.hashValue.description
            sharedStore.defaults.set(tokenHash, forKey: "pending_pause_token")
            sharedStore.defaults.set(
                application.hashValue.description,
                forKey: "pending_pause_app_hash"
            )
            
            // Check cooldown — if in cooldown, allow directly
            if sharedStore.isInCooldown(for: tokenHash) {
                sharedStore.confirmPause(appTokenHash: tokenHash)
                completionHandler(.close)
                return
            }
            
            // Defer to main app — the shield stays, user goes to our app
            // .defer keeps the shield while we open our app
            completionHandler(.defer)
            
        case .secondaryButtonPressed:
            // "Close" button — dismiss and go to home screen
            completionHandler(.close)
            
        @unknown default:
            completionHandler(.close)
        }
    }
    
    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            let tokenHash = webDomain.hashValue.description
            sharedStore.defaults.set(tokenHash, forKey: "pending_pause_token")
            
            if sharedStore.isInCooldown(for: tokenHash) {
                sharedStore.confirmPause(appTokenHash: tokenHash)
                completionHandler(.close)
                return
            }
            
            completionHandler(.defer)
            
        case .secondaryButtonPressed:
            completionHandler(.close)
            
        @unknown default:
            completionHandler(.close)
        }
    }
    
    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }
}