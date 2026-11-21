import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/utils/device_signals.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Automatic carrier/category collection is opt-in (SDKConfig.collectDeviceSignals).
// A workspace without audience signals rejects device.carrier / device.category,
// so an app that upgrades the SDK and changes nothing must send exactly what it
// sent before. These tests run against the SDK as an app gets it from
// AdMoai.initialize, with the native channel answering as a real phone would.

const _baseUrl = 'https://mock.api.admoai.com';

/// The request body captured from `main` before audience signals existed
/// (the same bytes as `_plainGolden` in audience_signals_golden_test.dart).
const _plainGolden =
    r'''{"placements":[{"key":"home","count":2}],"user":{"id":"user-1","ip":"203.0.113.7","timezone":"UTC","consent":{"gdpr":false}},"device":{"id":"dev-1","model":"Pixel 9","manufacturer":"Google","os":"android","osVersion":"15","timezone":"Europe/Madrid","language":"es"},"app":{"name":"Demo","version":"1.2.3","buildNumber":"45","identifier":"com.example.demo","language":"en"}}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const signals = MethodChannel('admoai/device_signals');
  const timezone = MethodChannel('flutter_timezone');

  var calls = 0;

  setUp(() {
    calls = 0;
    // The host behaves as a phone: the channel would be called if allowed.
    debugMobileHostOverride = true;
    messenger.setMockMethodCallHandler(signals, (call) async {
      calls++;
      return {'carrier': 'T-Mobile', 'category': 'tablet'};
    });
    messenger.setMockMethodCallHandler(timezone,
        (call) async => call.method == 'getLocalTimezone' ? 'UTC' : null);
  });

  tearDown(() {
    debugMobileHostOverride = null;
    messenger.setMockMethodCallHandler(signals, null);
    messenger.setMockMethodCallHandler(timezone, null);
  });

  /// Fills the pre-existing fields with the golden's values through the public
  /// API; carrier and category are left to whatever the SDK decided.
  void fillGoldenFields(AdMoai sdk) {
    sdk
      ..setAppConfig(
        name: 'Demo',
        version: '1.2.3',
        buildNumber: '45',
        identifier: 'com.example.demo',
        language: 'en',
      )
      ..setDeviceConfig(
        id: 'dev-1',
        model: 'Pixel 9',
        manufacturer: 'Google',
        os: 'android',
        osVersion: '15',
        timezone: 'Europe/Madrid',
        language: 'es',
      )
      ..setUserConfig(id: 'user-1', ip: '203.0.113.7', timezone: 'UTC');
  }

  String requestJson(AdMoai sdk) => jsonEncode((sdk.createRequestBuilder()
        ..addPlacement(key: 'home', count: 2))
      .build()
      .toJson());

  test('the default SDK never calls the channel and its request is unchanged',
      () async {
    final sdk = await AdMoai.initialize(config: SDKConfig(baseUrl: _baseUrl));
    expect(calls, 0);
    expect(sdk.deviceConfig.carrier, isNull);
    expect(sdk.deviceConfig.category, isNull);

    fillGoldenFields(sdk);
    expect(requestJson(sdk), _plainGolden);
  });

  test('resetDeviceConfig on the default SDK does not collect either',
      () async {
    final sdk = await AdMoai.initialize(config: SDKConfig(baseUrl: _baseUrl));
    await sdk.resetDeviceConfig();
    expect(calls, 0);
    expect(sdk.deviceConfig.carrier, isNull);
    expect(sdk.deviceConfig.category, isNull);
  });

  test('collectDeviceSignals: true collects and sends both fields', () async {
    final sdk = await AdMoai.initialize(
      config: SDKConfig(baseUrl: _baseUrl, collectDeviceSignals: true),
    );
    expect(calls, 1);
    fillGoldenFields(sdk);
    final device = jsonDecode(requestJson(sdk))['device'] as Map;
    expect(device['carrier'], 'T-Mobile');
    expect(device['category'], 'tablet');

    await sdk.resetDeviceConfig();
    expect(calls, 2);
    expect(sdk.deviceConfig.category, DeviceCategory.tablet);
  });

  test('a value set by hand is sent without opting in', () async {
    final sdk = await AdMoai.initialize(config: SDKConfig(baseUrl: _baseUrl));
    sdk.setDeviceConfig(carrier: 'Vodafone', category: DeviceCategory.phone);
    expect(calls, 0);
    final device = jsonDecode(requestJson(sdk))['device'] as Map;
    expect(device['carrier'], 'Vodafone');
    expect(device['category'], 'phone');
  });
}
