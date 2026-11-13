import Flutter
import UIKit

/// Exposes coarse device signals to the Dart SDK over `admoai/device_signals`.
/// No CoreTelephony: `carrier` is never returned on iOS.
///
/// Parity table (same rules as `AdmoaiPlugin.kt` and the Dart test):
///  - carrier: never provided on iOS.
///  - category: isiOSAppOnMac / Mac Catalyst -> "other"; idiom phone ->
///    "phone", pad -> "tablet", tv / carPlay / mac / vision -> "other".
///  - Android (for reference): carrier from the default-data subscription only
///    (API >= 24, telephony required); leanback / watch / automotive / pc ->
///    "other"; smallest full-display width < 600 dp phone, >= 600 dp tablet.
public class AdmoaiPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "admoai/device_signals", binaryMessenger: registrar.messenger())
    let instance = AdmoaiPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "collect" else {
      result(FlutterMethodNotImplemented)
      return
    }
    var out: [String: String] = [:]
    if let category = AdmoaiPlugin.category() {
      out["category"] = category
    }
    result(out)
  }

  static func category() -> String? {
    if #available(iOS 14.0, *) {
      if ProcessInfo.processInfo.isiOSAppOnMac { return "other" }
    }
    if #available(iOS 13.0, *) {
      if ProcessInfo.processInfo.isMacCatalystApp { return "other" }
    }
    switch UIDevice.current.userInterfaceIdiom {
    case .phone: return "phone"
    case .pad: return "tablet"
    case .tv, .carPlay: return "other"
    default:
      // .mac (iOS 14+) and .vision (iOS 17+) are not referenced by name so
      // the code compiles against every SDK; compare raw values instead.
      switch UIDevice.current.userInterfaceIdiom.rawValue {
      case 5, 6: return "other"  // .mac = 5, .vision = 6
      default: return nil
      }
    }
  }
}
