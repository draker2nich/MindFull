import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customizes the appearance of the shield overlay shown on blocked apps.
/// This is the iOS equivalent of PauseActivity's visual design.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    private var isRussian: Bool {
        Locale.current.language.languageCode?.identifier == "ru"
    }
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let appName = application.localizedDisplayName ?? (isRussian ? "приложение" : "app")
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.06, blue: 0.06, alpha: 0.95),
            icon: UIImage(systemName: "leaf.fill"),
            title: ShieldConfiguration.Label(
                text: isRussian ? "Сделай паузу" : "Take a pause",
                color: UIColor(red: 0.91, green: 0.94, blue: 0.93, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: isRussian
                    ? "Перед открытием \(appName)"
                    : "Before opening \(appName)",
                color: UIColor(red: 0.48, green: 0.58, blue: 0.56, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: isRussian ? "Начать паузу" : "Start pause",
                color: UIColor(red: 0.04, green: 0.06, blue: 0.06, alpha: 1.0)
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.43, green: 0.77, blue: 0.68, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: isRussian ? "Закрыть" : "Close",
                color: UIColor(red: 0.48, green: 0.58, blue: 0.56, alpha: 1.0)
            )
        )
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        // Same config for category-based shielding
        return configuration(shielding: application)
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.06, blue: 0.06, alpha: 0.95),
            icon: UIImage(systemName: "leaf.fill"),
            title: ShieldConfiguration.Label(
                text: isRussian ? "Сделай паузу" : "Take a pause",
                color: UIColor(red: 0.91, green: 0.94, blue: 0.93, alpha: 1.0)
            ),
            subtitle: ShieldConfiguration.Label(
                text: isRussian ? "Перед открытием сайта" : "Before opening this site",
                color: UIColor(red: 0.48, green: 0.58, blue: 0.56, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: isRussian ? "Начать паузу" : "Start pause",
                color: UIColor(red: 0.04, green: 0.06, blue: 0.06, alpha: 1.0)
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.43, green: 0.77, blue: 0.68, alpha: 1.0),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: isRussian ? "Закрыть" : "Close",
                color: UIColor(red: 0.48, green: 0.58, blue: 0.56, alpha: 1.0)
            )
        )
    }
}