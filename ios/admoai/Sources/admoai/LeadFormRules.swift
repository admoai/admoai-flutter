import Foundation

/// The pure decisions behind the secure form view, separated from WebKit so they run in a plain unit
/// test. Everything fails closed: anything that is not exactly what is expected is refused.
struct LeadFormOrigin: Equatable {
  let scheme: String
  let host: String
  let port: Int

  /// The origin of an https URL with a host and no user info; nil for anything else. The page's origin
  /// is the only one the bridge ever listens to.
  init?(url: URL) {
    guard let scheme = url.scheme?.lowercased(), scheme == "https",
      let host = url.host?.lowercased(), !host.isEmpty,
      url.user == nil, url.password == nil
    else { return nil }
    self.scheme = scheme
    self.host = host
    self.port = LeadFormOrigin.effectivePort(scheme: scheme, port: url.port ?? 0)
  }

  /// WebKit reports the default port as 0.
  static func effectivePort(scheme: String, port: Int) -> Int {
    if port != 0 { return port }
    return scheme == "https" ? 443 : 80
  }

  /// True when a frame's security origin (protocol, host, port) is exactly this origin.
  func matches(protocolName: String, host: String, port: Int) -> Bool {
    scheme == protocolName.lowercased() && self.host == host.lowercased()
      && self.port == LeadFormOrigin.effectivePort(scheme: protocolName.lowercased(), port: port)
  }
}

/// Lets a message through only when it comes from the main frame at the launch origin and is a text.
enum LeadFormGate {
  static func accept(
    isMainFrame: Bool, protocolName: String, host: String, port: Int, body: Any, launchOrigin: LeadFormOrigin
  ) -> String? {
    guard isMainFrame, launchOrigin.matches(protocolName: protocolName, host: host, port: port),
      let text = body as? String
    else { return nil }
    return text
  }
}

/// What the page's JavaScript sees: `window.AdmoaiBridge = { postMessage(text), addEventListener('message', fn) }`.
/// Injected in the main frame only, at document start. Replies arrive through `window.__admoaiDeliver`
/// as a `MessageEvent` whose `data` is the JSON string.
enum LeadFormScripts {
  static let bridge = """
    (function () {
      var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.AdmoaiBridge;
      if (!handler || window.AdmoaiBridge) { return; }
      var post = handler.postMessage.bind(handler);
      var listeners = [];
      var bridge = {
        postMessage: function (text) { post(text); },
        addEventListener: function (type, fn) {
          if (type === 'message' && typeof fn === 'function' && listeners.indexOf(fn) < 0) { listeners.push(fn); }
        },
        removeEventListener: function (type, fn) {
          var i = listeners.indexOf(fn);
          if (type === 'message' && i >= 0) { listeners.splice(i, 1); }
        }
      };
      Object.defineProperty(window, 'AdmoaiBridge', { value: bridge, enumerable: false, writable: false, configurable: false });
      Object.defineProperty(window, '__admoaiDeliver', {
        value: function (text) {
          var event = new MessageEvent('message', { data: text });
          listeners.slice().forEach(function (fn) { try { fn.call(bridge, event); } catch (e) {} });
          if (typeof bridge.onmessage === 'function') { try { bridge.onmessage(event); } catch (e) {} }
        },
        enumerable: false, writable: false, configurable: false
      });
    })();
    """
}

/// What the page and the view report to Dart, by the names the Dart side reads.
enum LeadFormEventKind: String {
  case message
  case renderGone
  case loadFailed
}
