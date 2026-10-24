import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Screen brightness before the player first changed it, restored by
  /// `reset` (on iOS the brightness is the whole screen's).
  private var brightnessBeforePlayer: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GhostlimeBrightness") {
      registerBrightnessChannel(messenger: registrar.messenger())
    }
  }

  /// Serves `ghostlime/brightness`: `get`, `set` (0 to 1) and `reset`.
  private func registerBrightnessChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ghostlime/brightness", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "get":
        result(Double(UIScreen.main.brightness))
      case "set":
        guard let value = call.arguments as? Double else {
          result(FlutterError(code: "bad_argument", message: "Expected a number", details: nil))
          return
        }
        if self.brightnessBeforePlayer == nil {
          self.brightnessBeforePlayer = UIScreen.main.brightness
        }
        UIScreen.main.brightness = CGFloat(min(max(value, 0.01), 1))
        result(nil)
      case "reset":
        if let previous = self.brightnessBeforePlayer {
          UIScreen.main.brightness = previous
          self.brightnessBeforePlayer = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
