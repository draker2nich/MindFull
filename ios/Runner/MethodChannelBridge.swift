import Flutter
import UIKit
import FamilyControls
import SwiftUI

/// Bridges Flutter MethodChannels to native iOS Screen Time API.
/// Mirrors the Android channel structure for compatibility.
@available(iOS 16.0, *)
final class MethodChannelBridge {
    
    private let manager = ScreenTimeManager.shared
    
    func register(with messenger: FlutterBinaryMessenger, controller: FlutterViewController) {
        setupPermissionsChannel(messenger)
        setupServiceChannel(messenger)
        setupAppsChannel(messenger, controller: controller)
    }
    
    // MARK: - Permissions Channel
    // Matches: com.example.mindfull/permissions
    
    private func setupPermissionsChannel(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.example.mindfull/permissions",
            binaryMessenger: messenger
        )
        
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterMethodNotImplemented); return }
            
            switch call.method {
            case "hasUsageAccess":
                // On iOS, Screen Time auth covers both usage access and overlay
                result(self.manager.isAuthorized)
                
            case "hasOverlayPermission":
                // Same auth on iOS
                result(self.manager.isAuthorized)
                
            case "hasBatteryOptimizationExemption":
                // Not applicable on iOS — always return true
                result(true)
                
            case "requestUsageAccess", "requestOverlayPermission":
                Task {
                    do {
                        try await self.manager.requestAuthorization()
                        DispatchQueue.main.async { result(nil) }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(
                                code: "AUTH_ERROR",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        }
                    }
                }
                
            case "requestBatteryOptimizationExemption":
                // No-op on iOS
                result(nil)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    // MARK: - Service Channel
    // Matches: com.example.mindfull/service
    
    private func setupServiceChannel(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.example.mindfull/service",
            binaryMessenger: messenger
        )
        
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterMethodNotImplemented); return }
            
            switch call.method {
            case "startService":
                do {
                    try self.manager.startMonitoring()
                    result(nil)
                } catch {
                    result(FlutterError(
                        code: "START_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
                
            case "stopService":
                self.manager.stopMonitoring()
                result(nil)
                
            case "isServiceRunning":
                result(self.manager.isMonitoring)
                
            case "updateMonitoredApps":
                // On iOS, apps are managed via FamilyActivitySelection, not package names.
                // This is called from Flutter but the actual selection happens via native picker.
                // We just re-apply shields if monitoring is active.
                if self.manager.isMonitoring {
                    self.manager.reapplyShieldIfNeeded()
                }
                result(nil)
                
            case "setCooldownMinutes":
                if let args = call.arguments as? [String: Any],
                   let minutes = args["minutes"] as? Int {
                    self.manager.setCooldownMinutes(minutes)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "minutes is null", details: nil))
                }
                
            case "getCooldownMinutes":
                result(SharedStore.shared.cooldownMinutes)
                
            case "setCooldownEnabled":
                if let args = call.arguments as? [String: Any],
                   let enabled = args["enabled"] as? Bool {
                    self.manager.setCooldownEnabled(enabled)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "enabled is null", details: nil))
                }
                
            case "isCooldownEnabled":
                result(SharedStore.shared.isCooldownEnabled)
                
            // iOS-specific: lift shield after pause completed
            case "liftShield":
                if let args = call.arguments as? [String: Any],
                   let tokenHash = args["tokenHash"] as? String {
                    self.manager.liftShield(for: tokenHash)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "tokenHash is null", details: nil))
                }
                
            case "getSelectedAppCount":
                result(self.manager.selectedAppCount)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    // MARK: - Apps Channel
    // Matches: com.example.mindfull/apps
    
    private func setupAppsChannel(_ messenger: FlutterBinaryMessenger, controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.example.mindfull/apps",
            binaryMessenger: messenger
        )
        
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterMethodNotImplemented); return }
            
            switch call.method {
            case "getInstalledApps":
                // On iOS, we can't list installed apps.
                // Return empty list — Flutter will show FamilyActivityPicker instead.
                result([])
                
            case "openFamilyActivityPicker":
                // Present the native SwiftUI FamilyActivityPicker
                DispatchQueue.main.async {
                    self.presentFamilyActivityPicker(from: controller, result: result)
                }
                
            case "getSelectedAppCount":
                result(self.manager.selectedAppCount)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    // MARK: - FamilyActivityPicker Presentation
    
    private func presentFamilyActivityPicker(from controller: FlutterViewController, result: @escaping FlutterResult) {
        let currentSelection = manager.loadSelection() ?? FamilyActivitySelection()
        
        let pickerView = FamilyActivityPickerWrapper(
            selection: currentSelection,
            onSave: { [weak self] newSelection in
                self?.manager.saveSelection(newSelection)
                result(newSelection.applicationTokens.count)
            },
            onCancel: {
                result(nil)
            }
        )
        
        let hostingController = UIHostingController(rootView: pickerView)
        hostingController.modalPresentationStyle = .pageSheet
        
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberIndicator = true
        }
        
        controller.present(hostingController, animated: true)
    }
}

// MARK: - SwiftUI Wrapper for FamilyActivityPicker

@available(iOS 16.0, *)
struct FamilyActivityPickerWrapper: View {
    @State var selection: FamilyActivitySelection
    let onSave: (FamilyActivitySelection) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle(isRussian ? "Выбор приложений" : "Select Apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isRussian ? "Отмена" : "Cancel") {
                            dismiss()
                            onCancel()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isRussian ? "Сохранить" : "Save") {
                            dismiss()
                            onSave(selection)
                        }
                        .bold()
                    }
                }
        }
    }
    
    private var isRussian: Bool {
        Locale.current.language.languageCode?.identifier == "ru"
    }
}