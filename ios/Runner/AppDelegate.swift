import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var storageChannel: FlutterMethodChannel?
  private var originalReaderBrightness: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    storageChannel = FlutterMethodChannel(
      name: "codar/storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setReaderBrightness",
            let arguments = call.arguments as? [String: Any],
            let value = arguments["brightness"] as? Double else {
        result(FlutterMethodNotImplemented)
        return
      }
      let screen = UIScreen.main
      if value < 0 {
        if let original = self?.originalReaderBrightness {
          screen.brightness = original
          self?.originalReaderBrightness = nil
        }
      } else {
        if self?.originalReaderBrightness == nil {
          self?.originalReaderBrightness = screen.brightness
        }
        screen.brightness = CGFloat(min(max(value, 0.05), 1.0))
      }
      result(nil)
    }
  }
}
