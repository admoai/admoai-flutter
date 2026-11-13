import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/utils/device_signals.dart';
import 'package:admoai/src/utils/device_signals_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('admoai/device_signals');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, Object?> native = {};
  var calls = 0;

  setUp(() {
    native = {'carrier': 'Auto Telco', 'category': 'tablet'};
    calls = 0;
    debugMobileHostOverride = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return native;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => call.method == 'getLocalTimezone' ? 'UTC' : null,
    );
  });
  tearDown(() {
    debugMobileHostOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  // These tests cover the opted-in behaviour; the default SDK (opt-in off) is
  // covered by device_signals_opt_in_test.dart and the default-SDK group below.
  Future<AdMoai> init() => AdMoai.initialize(
      config: SDKConfig(
          baseUrl: 'https://mock.api.admoai.com', collectDeviceSignals: true));

  Map<String, dynamic> device(AdMoai sdk) {
    final b = sdk.createRequestBuilder()..addPlacement(key: 'p');
    return (jsonDecode(jsonEncode(b.build().toJson()))
        as Map<String, dynamic>)['device'] as Map<String, dynamic>;
  }

  test('systemDefault fills carrier and category and turns auto on', () async {
    final c = await DeviceConfig.systemDefault(collectSignals: true);
    expect(c.carrier, 'Auto Telco');
    expect(c.category, DeviceCategory.tablet);
    expect(autoStateOf(c).auto, isTrue);
  });

  test('systemDefault on a non-mobile host does not call the channel',
      () async {
    debugMobileHostOverride = false;
    final c = await DeviceConfig.systemDefault(collectSignals: true);
    expect(calls, 0);
    expect(c.carrier, isNull);
    expect(c.category, isNull);
    expect(autoStateOf(c).auto, isTrue);
  });

  test('channel failure keeps existing device fields', () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => throw PlatformException(code: 'boom'));
    final sdk = await init();
    sdk.setDeviceConfig(id: 'd1', model: 'M');
    expect(sdk.deviceConfig.carrier, isNull);
    expect(sdk.deviceConfig.category, isNull);
    final d = device(sdk);
    expect(d['id'], 'd1');
    expect(d['model'], 'M');
    expect(d.containsKey('carrier'), isFalse);
    expect(d.containsKey('category'), isFalse);
  });

  test('default constructor and clear() have auto off', () {
    expect(autoStateOf(DeviceConfig()).auto, isFalse);
    expect(autoStateOf(DeviceConfig.clear()).auto, isFalse);
  });

  test('manual values win and survive setDeviceConfig of other fields',
      () async {
    final sdk = await init();
    sdk.setDeviceConfig(carrier: 'Manual Co');
    expect(sdk.deviceConfig.carrier, 'Manual Co');
    expect(sdk.deviceConfig.category, DeviceCategory.tablet);
    final s = autoStateOf(sdk.deviceConfig);
    expect(s.auto, isTrue);
    expect(s.manualCarrier, isTrue);
    expect(s.manualCategory, isFalse);
    sdk.setDeviceConfig(model: 'X');
    expect(autoStateOf(sdk.deviceConfig).manualCarrier, isTrue);
  });

  test('auto refresh never overwrites manual fields', () async {
    final sdk = await init();
    sdk.setDeviceConfig(category: DeviceCategory.phone);
    native = {'carrier': 'New Telco', 'category': 'other'};
    final refreshed = await refreshAutoSignals(sdk.deviceConfig);
    expect(refreshed.category, DeviceCategory.phone);
    expect(refreshed.carrier, 'New Telco');
  });

  test('refresh on an auto-off config is a no-op', () async {
    final c = DeviceConfig(carrier: 'X');
    expect(identical(await refreshAutoSignals(c), c), isTrue);
    expect(calls, 0);
  });

  test('clearDeviceConfig: no auto, both absent', () async {
    final sdk = await init();
    sdk.clearDeviceConfig();
    expect(autoStateOf(sdk.deviceConfig).auto, isFalse);
    expect(sdk.deviceConfig.carrier, isNull);
    expect(sdk.deviceConfig.category, isNull);
    final before = calls;
    expect(
        identical(await refreshAutoSignals(sdk.deviceConfig), sdk.deviceConfig),
        isTrue);
    expect(calls, before);
  });

  test('setDeviceConfig after clear stays auto off', () async {
    final sdk = await init();
    sdk.clearDeviceConfig();
    sdk.setDeviceConfig(carrier: 'Manual Co');
    expect(autoStateOf(sdk.deviceConfig).auto, isFalse);
  });

  test('resetDeviceConfig: auto on, fresh read, manual discarded', () async {
    final sdk = await init();
    sdk.setDeviceConfig(carrier: 'Manual Co', category: DeviceCategory.phone);
    native = {'carrier': 'Fresh Telco', 'category': 'other'};
    await sdk.resetDeviceConfig();
    expect(sdk.deviceConfig.carrier, 'Fresh Telco');
    expect(sdk.deviceConfig.category, DeviceCategory.other);
    final s = autoStateOf(sdk.deviceConfig);
    expect(s.auto, isTrue);
    expect(s.manualCarrier, isFalse);
    expect(s.manualCategory, isFalse);
  });

  test('disableDeviceCollection omits the whole device, new fields included',
      () async {
    final sdk = await init();
    sdk.setDeviceConfig(carrier: 'Manual Co', category: DeviceCategory.phone);
    final b = sdk.createRequestBuilder()
      ..addPlacement(key: 'p')
      ..disableDeviceCollection();
    final json = jsonDecode(jsonEncode(b.build().toJson())) as Map;
    expect(json.containsKey('device'), isFalse);
  });

  group('requestAds refreshes auto signals', () {
    late List<Map<String, dynamic>> bodies;
    late MockClient client;

    setUp(() {
      bodies = [];
      client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"success":true,"data":{"placements":[]}}', 200,
            headers: {'content-type': 'application/json'});
      });
    });

    Future<AdMoai> initWithClient({bool optIn = true}) => AdMoai.initialize(
        config: SDKConfig(
            baseUrl: 'https://mock.api.admoai.com',
            collectDeviceSignals: optIn),
        httpClient: client);

    DecisionRequest build(AdMoai sdk, {bool disableDevice = false}) {
      final b = sdk.createRequestBuilder()..addPlacement(key: 'p');
      if (disableDevice) b.disableDeviceCollection();
      return b.build();
    }

    Map<String, dynamic>? sentDevice() =>
        bodies.last['device'] as Map<String, dynamic>?;

    test('(0) default SDK: no channel call and no carrier or category, ever',
        () async {
      final sdk = await initWithClient(optIn: false);
      expect(autoStateOf(sdk.deviceConfig).auto, isFalse);
      native = {'carrier': 'New Telco', 'category': 'phone'};
      await sdk.requestAds(build(sdk));
      await sdk.requestAds(build(sdk));
      expect(calls, 0);
      expect(sentDevice()!.containsKey('carrier'), isFalse);
      expect(sentDevice()!.containsKey('category'), isFalse);
    });

    test('(a) fresh native answer reaches the body and the snapshot', () async {
      final sdk = await initWithClient();
      final request = build(sdk);
      native = {'carrier': 'New Telco', 'category': 'phone'};
      await sdk.requestAds(request);
      expect(sentDevice()!['carrier'], 'New Telco');
      expect(sentDevice()!['category'], 'phone');
      expect(sdk.deviceConfig.carrier, 'New Telco');
      expect(sdk.deviceConfig.category, DeviceCategory.phone);
    });

    test('(b) a slow native read keeps the snapshot and does not wait',
        () async {
      final sdk = await initWithClient();
      final request = build(sdk);
      messenger.setMockMethodCallHandler(channel, (call) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return {'carrier': 'Late Telco', 'category': 'phone'};
      });
      final sw = Stopwatch()..start();
      await sdk.requestAds(request);
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(sentDevice()!['carrier'], 'Auto Telco');
      expect(sentDevice()!['category'], 'tablet');
      expect(sdk.deviceConfig.carrier, 'Auto Telco');
    });

    test('(c) a native PlatformException keeps the previous snapshot',
        () async {
      final sdk = await initWithClient();
      final request = build(sdk);
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom'));
      await sdk.requestAds(request);
      expect(sentDevice()!['carrier'], 'Auto Telco');
      expect(sentDevice()!['category'], 'tablet');
    });

    test('(d) an answer without carrier removes it from the body', () async {
      final sdk = await initWithClient();
      final request = build(sdk);
      native = {'category': 'tablet'};
      await sdk.requestAds(request);
      expect(sentDevice()!.containsKey('carrier'), isFalse);
      expect(sentDevice()!['category'], 'tablet');
      expect(sdk.deviceConfig.carrier, isNull);
    });

    test('(e) a manual carrier is never overwritten', () async {
      final sdk = await initWithClient();
      sdk.setDeviceConfig(carrier: 'Manual Co');
      final request = build(sdk);
      native = {'carrier': 'New Telco', 'category': 'phone'};
      await sdk.requestAds(request);
      expect(sentDevice()!['carrier'], 'Manual Co');
      expect(sentDevice()!['category'], 'phone');
      expect(sdk.deviceConfig.carrier, 'Manual Co');
    });

    test('(f) clearDeviceConfig: no channel call, no carrier or category',
        () async {
      final sdk = await initWithClient();
      sdk.clearDeviceConfig();
      final request = build(sdk);
      final before = calls;
      await sdk.requestAds(request);
      expect(calls, before);
      expect(sentDevice()!.containsKey('carrier'), isFalse);
      expect(sentDevice()!.containsKey('category'), isFalse);
    });

    test('(g) disableDeviceCollection sends no device object', () async {
      final sdk = await initWithClient();
      final request = build(sdk, disableDevice: true);
      native = {'carrier': 'New Telco', 'category': 'phone'};
      await sdk.requestAds(request);
      expect(bodies.last.containsKey('device'), isFalse);
    });

    test("(h) the caller's request is not mutated", () async {
      final sdk = await initWithClient();
      final request = build(sdk);
      final device = request.device;
      final before = jsonEncode(request.toJson());
      native = {'carrier': 'New Telco', 'category': 'phone'};
      await sdk.requestAds(request);
      expect(identical(request.device, device), isTrue);
      expect(jsonEncode(request.toJson()), before);
      expect(request.device!.carrier, 'Auto Telco');
    });
  });
}
