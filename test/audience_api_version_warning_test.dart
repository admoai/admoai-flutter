import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

/// Audience signals sent without `apiVersion` reach the default route: matched,
/// but not recorded as audience dimensions. The SDK warns once per request, the
/// same way it warns for Journey context.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;

  const needle = 'Audience signals set but apiVersion is null';

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'), (_) async => 'UTC');
  });

  ({Logger logger, List<LogRecord> records}) capture(String name) {
    final records = <LogRecord>[];
    final logger = Logger(name)
      ..level = Level.ALL
      ..onRecord.listen(records.add);
    return (logger: logger, records: records);
  }

  AdMoai sdkWith(Logger logger, {String? apiVersion}) => AdMoai.forTesting(
        config: SDKConfig(
            baseUrl: 'https://mock.api.admoai.com',
            apiVersion: apiVersion,
            logger: logger),
        httpClient: MockClient(
            (r) async => http.Response('{"success":true,"data":[]}', 200)),
      );

  int warnings(List<LogRecord> records) => records
      .where((r) => r.level >= Level.WARNING && r.message.contains(needle))
      .length;

  final cases =
      <String, DecisionRequestBuilder Function(DecisionRequestBuilder)>{
    'a Standard key (typed setter)': (b) => b.setAgeGroup(AgeGroup.age25To34),
    'a Standard key (generic addCustomTargeting)': (b) =>
        b.addCustomTargeting(key: 'activity_frequency_30d', value: '0'),
    'publisher segments': (b) => b.setPublisherSegments(['beach_goer']),
  };

  for (final entry in cases.entries) {
    test('requestAds with ${entry.key} and no apiVersion warns once', () async {
      final log = capture('aw-${entry.key}');
      final sdk = sdkWith(log.logger);
      final request = entry
          .value(sdk.createRequestBuilder().addPlacement(key: 'home'))
          .build();
      await sdk.requestAds(request);
      expect(warnings(log.records), 1);
    });
  }

  test('getHttpRequest with a Standard key and no apiVersion warns', () {
    final log = capture('aw-gethttp');
    final sdk = sdkWith(log.logger);
    sdk.getHttpRequest(sdk
        .createRequestBuilder()
        .addPlacement(key: 'home')
        .setGender(Gender.female)
        .build());
    expect(warnings(log.records), 1);
  });

  test('a device category set by hand and no apiVersion warns', () async {
    final log = capture('aw-device');
    final sdk = sdkWith(log.logger);
    sdk.setDeviceConfig(category: DeviceCategory.tablet);
    await sdk.requestAds(
        sdk.createRequestBuilder().addPlacement(key: 'home').build());
    expect(warnings(log.records), 1);
  });

  test('no warning when apiVersion is set', () async {
    final log = capture('aw-versioned');
    final sdk = sdkWith(log.logger, apiVersion: '2025-11-01');
    sdk.setDeviceConfig(carrier: 'Example Mobile');
    await sdk.requestAds(sdk
        .createRequestBuilder()
        .addPlacement(key: 'home')
        .setAgeGroup(AgeGroup.age25To34)
        .build());
    expect(warnings(log.records), 0);
  });

  test('no warning for a request with only non-audience custom keys', () async {
    final log = capture('aw-custom');
    final sdk = sdkWith(log.logger);
    await sdk.requestAds(sdk
        .createRequestBuilder()
        .addPlacement(key: 'home')
        .addCustomTargeting(key: 'category', value: 'news')
        .build());
    expect(warnings(log.records), 0);
  });
}
