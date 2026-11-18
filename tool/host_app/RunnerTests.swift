// XCTest for the plugin's iOS device signals. tool/host_app.sh copies this file
// over the generated host app's ios/RunnerTests/RunnerTests.swift; the iOS CI job
// runs it on a simulator (`xcodebuild test`). Same rules as AdmoaiPlugin.kt and
// the Dart parity table in test/device_signals_test.dart.
import Flutter
import UIKit
import XCTest
import admoai

class RunnerTests: XCTestCase {

  private func category(_ idiom: Int, onMac: Bool = false, catalyst: Bool = false)
    -> String?
  {
    AdmoaiPlugin.category(idiomRawValue: idiom, isiOSAppOnMac: onMac, isMacCatalyst: catalyst)
  }

  func testPhoneIdiomIsPhone() {
    XCTAssertEqual(category(UIUserInterfaceIdiom.phone.rawValue), "phone")
  }

  func testPadIdiomIsTablet() {
    XCTAssertEqual(category(UIUserInterfaceIdiom.pad.rawValue), "tablet")
  }

  func testTvAndCarPlayAreOther() {
    XCTAssertEqual(category(UIUserInterfaceIdiom.tv.rawValue), "other")
    XCTAssertEqual(category(UIUserInterfaceIdiom.carPlay.rawValue), "other")
  }

  func testMacAndVisionRawValuesAreOther() {
    // .mac = 5 (iOS 14+), .vision = 6 (iOS 17+): the plugin matches raw values.
    XCTAssertEqual(category(5), "other")
    XCTAssertEqual(category(6), "other")
    if #available(iOS 14.0, *) {
      XCTAssertEqual(UIUserInterfaceIdiom.mac.rawValue, 5)
    }
  }

  func testUnspecifiedOrUnknownIdiomIsAbsent() {
    XCTAssertNil(category(UIUserInterfaceIdiom.unspecified.rawValue))
    XCTAssertNil(category(4))
    XCTAssertNil(category(99))
  }

  func testIPadAppOnMacOrCatalystIsOtherWhateverTheIdiom() {
    XCTAssertEqual(category(UIUserInterfaceIdiom.pad.rawValue, onMac: true), "other")
    XCTAssertEqual(category(UIUserInterfaceIdiom.phone.rawValue, catalyst: true), "other")
  }

  /// On the simulator running this test: never a carrier, and the category is
  /// the one the idiom of this device gives.
  func testCollectNeverSendsACarrier() {
    let out = AdmoaiPlugin.collect()
    XCTAssertNil(out["carrier"])
    XCTAssertTrue(Set(out.keys).isSubset(of: ["category"]))
    let expected = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
    XCTAssertEqual(out["category"], expected)
  }

  /// The channel answer is the same map: no carrier key.
  func testChannelCollectAnswersWithoutCarrier() {
    let done = expectation(description: "collect answered")
    AdmoaiPlugin().handle(FlutterMethodCall(methodName: "collect", arguments: nil)) {
      value in
      let map = value as? [String: String]
      XCTAssertNotNil(map)
      XCTAssertNil(map?["carrier"])
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }
}
