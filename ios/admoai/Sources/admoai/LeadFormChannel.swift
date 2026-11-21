import Flutter
import UIKit

/// The secure views one engine owns, by the id Dart gave them. Main thread only.
final class LeadFormViews {
  /// `SecureFormWebView` is iOS 14+; stored type-erased so the registry compiles on iOS 12.
  private var views: [String: AnyObject] = [:]
  private var destroyers: [String: () -> Void] = [:]

  @available(iOS 14.0, *)
  func put(_ id: String, _ view: SecureFormWebView) {
    remove(id)
    views[id] = view
    destroyers[id] = { view.destroy() }
  }

  @available(iOS 14.0, *)
  func get(_ id: String) -> SecureFormWebView? {
    views[id] as? SecureFormWebView
  }

  func uiView(_ id: String) -> UIView? {
    if #available(iOS 14.0, *) {
      return get(id)?.webView
    }
    return nil
  }

  func remove(_ id: String) {
    destroyers.removeValue(forKey: id)?()
    views.removeValue(forKey: id)
  }

  func removeAll() {
    for id in Array(views.keys) { remove(id) }
  }
}

/// `admoai/lead_form`: the channel Dart drives the secure views with. Every failure is reported as a
/// code only; a URL, a message or a token never appears in an error.
final class LeadFormChannel: NSObject, FlutterPlugin {
  static let channelName = "admoai/lead_form"
  static let viewType = "admoai/lead_form_view"

  let views = LeadFormViews()
  private let channel: FlutterMethodChannel

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = LeadFormChannel(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(LeadFormViewFactory(views: instance.views), withId: viewType)
  }

  /// iOS 14 and later: the form needs `callAsyncJavaScript`. Below that the SDK does not advertise.
  static func isSupported() -> Bool {
    if #available(iOS 14.0, *) { return true }
    return false
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "isSupported":
      result(LeadFormChannel.isSupported())
    case "create":
      create(id: args?["id"] as? String, url: args?["url"] as? String, result: result)
    case "post":
      guard #available(iOS 14.0, *), let id = args?["id"] as? String,
        let text = args?["text"] as? String, let view = views.get(id)
      else {
        result(FlutterError(code: "no_view", message: nil, details: nil))
        return
      }
      view.send(text)
      result(nil)
    case "destroy":
      if let id = args?["id"] as? String { views.remove(id) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func create(id: String?, url: String?, result: FlutterResult) {
    guard #available(iOS 14.0, *) else {
      result(FlutterError(code: "unsupported", message: nil, details: nil))
      return
    }
    guard let id = id, let url = url, let launch = URL(string: url) else {
      result(FlutterError(code: "bad_arguments", message: nil, details: nil))
      return
    }
    guard
      let view = SecureFormWebView(
        launchURL: launch,
        onEvent: { [weak self] kind, text in self?.emit(id: id, kind: kind, text: text) })
    else {
      result(FlutterError(code: "create_failed", message: nil, details: nil))
      return
    }
    views.put(id, view)
    view.load()
    result(nil)
  }

  private func emit(id: String, kind: LeadFormEventKind, text: String?) {
    var args: [String: String] = ["id": id, "kind": kind.rawValue]
    if let text = text { args["text"] = text }
    channel.invokeMethod("event", arguments: args)
  }
}

/// Hands out the view the controller created for `{id}` and never creates one. A request for an id
/// with no view (or a malformed one) gets an empty view: fail closed.
final class LeadFormViewFactory: NSObject, FlutterPlatformViewFactory {
  private let views: LeadFormViews

  init(views: LeadFormViews) {
    self.views = views
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let id = (args as? [String: Any])?["id"] as? String
    let existing = id.flatMap { views.uiView($0) }
    return AttachedView(existing ?? UIView(frame: frame))
  }
}

/// Attaches an existing view; the controller owns it, so it is never destroyed here.
final class AttachedView: NSObject, FlutterPlatformView {
  private let attached: UIView

  init(_ attached: UIView) {
    self.attached = attached
    super.init()
  }

  func view() -> UIView { attached }
}
