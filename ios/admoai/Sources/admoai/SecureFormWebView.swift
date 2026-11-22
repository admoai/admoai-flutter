import Flutter
import UIKit
import WebKit

/// Forwards script messages without letting the user content controller retain the view.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: WKScriptMessageHandler?

  init(_ target: WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

/// The secure form view: a WKWebView that only the form's own origin can talk to.
///
/// - One injected object, `AdmoaiBridge`, exists only in the main frame; the app listens only to the
///   main frame at the launch origin and only to text messages.
/// - Only the initial launch URL loads in the main frame; every other navigation, popup and frame
///   load is cancelled. Website data is never persisted. The view is never inspectable.
///
/// Nothing the page sends and no URL with a query string is ever logged. Main thread only.
@available(iOS 14.0, *)
final class SecureFormWebView: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
  static let bridgeName = "AdmoaiBridge"

  let webView: WKWebView
  private let launchURL: URL
  private let launchOrigin: LeadFormOrigin
  private let onEvent: (LeadFormEventKind, String?) -> Void
  private var launchConsumed = false
  private var destroyed = false

  /// nil when [launchURL] is not an https URL with a host.
  init?(launchURL: URL, onEvent: @escaping (LeadFormEventKind, String?) -> Void) {
    guard let origin = LeadFormOrigin(url: launchURL) else { return nil }
    self.launchURL = launchURL
    self.launchOrigin = origin
    self.onEvent = onEvent

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.dataDetectorTypes = []
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()

    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsLinkPreview = false
    if #available(iOS 16.4, *) {
      webView.isInspectable = false
    }
    let controller = configuration.userContentController
    controller.add(WeakScriptMessageHandler(self), name: SecureFormWebView.bridgeName)
    controller.addUserScript(
      WKUserScript(
        source: LeadFormScripts.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
  }

  /// Loads the launch URL: the one load this view ever makes.
  func load() {
    guard !destroyed else { return }
    webView.load(URLRequest(url: launchURL))
  }

  /// Sends one text to the page. The text is an argument, never part of the script source.
  func send(_ text: String) {
    guard !destroyed else { return }
    webView.callAsyncJavaScript(
      "window.__admoaiDeliver(text)", arguments: ["text": text], in: nil, in: .page
    ) { _ in }
  }

  /// Removes the bridge, stops loading and releases the view. Safe to repeat.
  func destroy() {
    guard !destroyed else { return }
    destroyed = true
    let controller = webView.configuration.userContentController
    controller.removeScriptMessageHandler(forName: SecureFormWebView.bridgeName)
    controller.removeAllUserScripts()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()
  }

  // MARK: WKScriptMessageHandler

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard !destroyed, message.name == SecureFormWebView.bridgeName else { return }
    let origin = message.frameInfo.securityOrigin
    guard
      let text = LeadFormGate.accept(
        isMainFrame: message.frameInfo.isMainFrame, protocolName: origin.protocol,
        host: origin.host, port: origin.port, body: message.body, launchOrigin: launchOrigin)
    else { return }
    onEvent(.message, text)
  }

  // MARK: WKNavigationDelegate

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    // Only the initial main-frame load of the launch URL; everything else (links, redirects,
    // script navigations, frames) is cancelled.
    if !destroyed, !launchConsumed, navigationAction.targetFrame?.isMainFrame == true,
      navigationAction.request.url == launchURL
    {
      launchConsumed = true
      decisionHandler(.allow)
    } else {
      decisionHandler(.cancel)
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if navigationResponse.isForMainFrame,
      let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400
    {
      decisionHandler(.cancel)
      fail("http:\(http.statusCode)")
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failUnlessCancelled(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failUnlessCancelled(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard !destroyed else { return }
    let callback = onEvent
    destroy()
    callback(.renderGone, nil)
  }

  // MARK: WKUIDelegate

  /// No popups, ever.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    nil
  }

  /// The SDK's own policy cancels (a link, a redirect, a refused response) come back as a failed
  /// navigation: they are not a load failure and are never reported.
  private func failUnlessCancelled(_ error: Error) {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
    if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
    fail("network")
  }

  /// The reason travels as the event's text: "http:<status>" or "network".
  private func fail(_ reason: String) {
    if !destroyed { onEvent(.loadFailed, reason) }
  }
}
