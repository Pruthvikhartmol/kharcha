import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let shareChannel = FlutterMethodChannel(
      name: "com.kharcha.expensetracker/share",
      binaryMessenger: messenger
    )
    shareChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "takePendingShares":
        let suite = UserDefaults(suiteName: AppDelegate.appGroupId)
        let pending = suite?.stringArray(forKey: AppDelegate.pendingSharesKey) ?? []
        suite?.removeObject(forKey: AppDelegate.pendingSharesKey)
        result(pending)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Shared with the Share Extension target — both must use the same App
  // Group id and key for the handoff to work.
  static let appGroupId = "group.com.kharcha.expensetracker"
  static let pendingSharesKey = "pendingShares"
}
