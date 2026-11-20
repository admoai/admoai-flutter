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
///    (API >= 24, telephony required); leanback / watch / automotive / pc
///    feature or TELEVISION / WATCH UI mode -> "other" (never CAR or DESK);
///    otherwise smallest full-display width < 600 dp phone, >= 600 dp tablet.
public class AdmoaiPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "admoai/device_signals", binaryMessenger: registrar.messenger())
    let instance = AdmoaiPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // The Lead Generation secure form view (channel `admoai/lead_form`, view type
    // `admoai/lead_form_view`); independent of the device signals above.
    LeadFormChannel.register(with: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "collect" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(AdmoaiPlugin.collect())
  }

  /// The map sent back on `collect`. Only `category`, when known: there is no
  /// `carrier` key on iOS, ever.
  public static func collect() -> [String: String] {
    var out: [String: String] = [:]
    if let category = category() {
      out["category"] = category
    }
    return out
  }

  /// The category of the device this process runs on.
  static func category() -> String? {
    var onMac = false
    if #available(iOS 14.0, *) {
      onMac = ProcessInfo.processInfo.isiOSAppOnMac
    }
    var catalyst = false
    if #available(iOS 13.0, *) {
      catalyst = ProcessInfo.processInfo.isMacCatalystApp
    }
    return category(
      idiomRawValue: UIDevice.current.userInterfaceIdiom.rawValue,
      isiOSAppOnMac: onMac,
      isMacCatalyst: catalyst)
  }

  /// The pure rule, from raw inputs (tested by `tool/host_app/RunnerTests.swift`).
  /// An iPad app on a Mac or a Catalyst app -> "other"; idiom phone (0) ->
  /// "phone", pad (1) -> "tablet", tv (2), carPlay (3), mac (5) and vision (6)
  /// -> "other"; anything else (unspecified -1, a future idiom) -> absent.
  /// Raw values keep the code compiling against every SDK, since `.mac` and
  /// `.vision` do not exist on older ones. An iPhone-only app on an iPad runs
  /// with the phone idiom, so it reports "phone".
  public static func category(
    idiomRawValue: Int, isiOSAppOnMac: Bool, isMacCatalyst: Bool
  ) -> String? {
    if isiOSAppOnMac || isMacCatalyst { return "other" }
    switch idiomRawValue {
    case 0: return "phone"
    case 1: return "tablet"
    case 2, 3, 5, 6: return "other"
    default: return nil
    }
  }
}
