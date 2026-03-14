import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    
    private var bridge: Any? // Type-erased to avoid @available on stored property
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        
        // Register MethodChannels
        if #available(iOS 16.0, *) {
            if let controller = window?.rootViewController as? FlutterViewController {
                let channelBridge = MethodChannelBridge()
                channelBridge.register(
                    with: controller.binaryMessenger,
                    controller: controller
                )
                self.bridge = channelBridge
            }
        }
    }
}