import 'package:admoai/admoai.dart';
import 'package:admoai/src/utils/device_signals.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Parity table: the Dart contract mirrors the native rules.
//
// Android (AdmoaiPlugin.kt, DeviceSignalRules)
//   carrier : default-data subscription only; API >= 24; no telephony -> absent
//   category: leanback / watch / automotive / pc -> other;
//             smallest full-display width < 600 dp -> phone, >= 600 dp -> tablet
// iOS (AdmoaiPlugin.swift)
//   carrier : never provided
//   category: isiOSAppOnMac / Catalyst -> other;
//             idiom phone / pad / tv / carPlay / mac / vision
// Dart side: carrier goes through normalizeCarrier; category is an exact-match
// wire parse; anything else is absent.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('admoai/device_signals');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  var calls = 0;
  void reply(Object? Function() fn) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'collect');
      return fn();
    });
  }

  setUp(() {
    calls = 0;
    debugMobileHostOverride = true;
  });
  tearDown(() {
    debugMobileHostOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<DeviceSignals> collectWith(Map<String, Object?> map) {
    reply(() => map);
    return collectDeviceSignals().then((s) => s!);
  }

  test('success map yields typed values', () async {
    final s = await collectWith({'carrier': 'Telco', 'category': 'phone'});
    expect(s.carrier, 'Telco');
    expect(s.category, DeviceCategory.phone);
  });

  test('carrier is trimmed', () async {
    expect((await collectWith({'carrier': '  Example Mobile '})).carrier,
        'Example Mobile');
  });

  for (final placeholder in ['--', ' WiFi ', 'unknown', '']) {
    test('carrier placeholder "$placeholder" is absent', () async {
      expect((await collectWith({'carrier': placeholder})).carrier, isNull);
    });
  }

  test('category tablet parses; other forms are absent', () async {
    expect((await collectWith({'category': 'tablet'})).category,
        DeviceCategory.tablet);
    for (final bad in <Object?>['TABLET', 'watch', null, 3]) {
      expect((await collectWith({'category': bad})).category, isNull,
          reason: '$bad');
    }
  });

  test('non-string carrier is absent', () async {
    expect((await collectWith({'carrier': 3})).carrier, isNull);
  });

  test('null reply is empty', () async {
    reply(() => null);
    final s = (await collectDeviceSignals())!;
    expect(s.carrier, isNull);
    expect(s.category, isNull);
  });

  test('PlatformException is a failed read (null)', () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => throw PlatformException(code: 'boom'));
    expect(await collectDeviceSignals(), isNull);
  });

  test('missing plugin is a failed read (null)', () async {
    expect(await collectDeviceSignals(), isNull);
  });

  test('timeout is a failed read (null), honoring the named parameter',
      () async {
    reply(() => {'category': 'phone'});
    messenger.setMockMethodCallHandler(channel, (call) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return {'category': 'phone'};
    });
    final sw = Stopwatch()..start();
    final s =
        await collectDeviceSignals(timeout: const Duration(milliseconds: 50));
    expect(s, isNull);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('non-mobile host never calls the channel', () async {
    debugMobileHostOverride = null;
    reply(() => {'carrier': 'Telco', 'category': 'phone'});
    final s = (await collectDeviceSignals(isMobileHost: () => false))!;
    expect(calls, 0);
    expect(s.carrier, isNull);
    expect(s.category, isNull);
  });

  test('DeviceCategory.fromWire is exact match only', () {
    expect(DeviceCategory.fromWire('phone'), DeviceCategory.phone);
    expect(DeviceCategory.fromWire('other'), DeviceCategory.other);
    expect(DeviceCategory.fromWire('Phone'), isNull);
    expect(DeviceCategory.fromWire(' phone'), isNull);
    expect(DeviceCategory.fromWire(null), isNull);
  });
}
