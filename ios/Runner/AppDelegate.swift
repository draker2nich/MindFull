import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    
    /// Stored as Any to avoid @available requirement on stored properties
    private var _bridge: Any?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerMethodChannels(pluginRegistry: engineBridge.pluginRegistry)
    }
    
    private func registerMethodChannels(pluginRegistry: FlutterPluginRegistry) {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        
        if #available(iOS 16.0, *) {
            let bridge = MethodChannelBridge()
            bridge.register(with: controller.binaryMessenger, controller: controller)
            _bridge = bridge
        } else {
            // iOS < 16: register stub channels that return "not supported" errors
            registerStubChannels(messenger: controller.binaryMessenger)
        }
    }
    
    /// Fallback for iOS < 16 where Screen Time API is unavailable
    private func registerStubChannels(messenger: FlutterBinaryMessenger) {
        let channelNames = [
            "com.example.mindfull/permissions",
            "com.example.mindfull/service",
            "com.example.mindfull/apps",
        ]
        
        for name in channelNames {
            let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
            channel.setMethodCallHandler { call, result in
                switch call.method {
                case "hasUsageAccess", "hasOverlayPermission", "isServiceRunning", "isCooldownEnabled":
                    result(false)
                case "hasBatteryOptimizationExemption":
                    result(true)
                case "getCooldownMinutes":
                    result(5)
                case "getInstalledApps":
                    result([])
                case "getSelectedAppCount":
                    result(0)
                default:
                    result(FlutterError(
                        code: "UNSUPPORTED",
                        message: "Screen Time API requires iOS 16.0+",
                        details: nil
                    ))
                }
            }
        }
    }
}