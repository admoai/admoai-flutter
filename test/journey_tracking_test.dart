import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

const baseUrl = 'https://mock.api.admoai.com';

Tracking trackingWith({List<Map<String, String>>? completions}) {
  return Tracking.fromJson({
    'impressions': [
      {'key': 'default', 'url': 'https://t.example/v1/tracking?e=imp'}
    ],
    if (completions != null) 'completions': completions,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;

  setUp(() {
    const MethodChannel channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getLocalTimezone') return 'UTC';
      return null;
    });
  });

  group('Tracking.completions parsing', () {
    test('parses completions array and resolves URL by key', () {
      final tracking = trackingWith(completions: [
        {'key': 'purchase', 'url': 'https://t.example/v1/tracking?e=cmp'},
      ]);

      expect(tracking.completions, isNotNull);
      expect(tracking.getCompletionUrl(key: 'purchase'),
          equals('https://t.example/v1/tracking?e=cmp'));
      expect(tracking.hasTrackingFor(TrackingType.completion, 'purchase'),
          isTrue);
      expect(tracking.getTrackingUrl(TrackingType.completion, 'purchase'),
          equals('https://t.example/v1/tracking?e=cmp'));
    });

    test('completions absent is backward compatible', () {
      final tracking = trackingWith();
      expect(tracking.completions, isNull);
      expect(tracking.getCompletionUrl(key: 'x'), isNull);
      expect(tracking.hasTrackingFor(TrackingType.completion, 'x'), isFalse);
    });

    test('malformed completion entries are dropped, not thrown (tolerant)', () {
      late Tracking tracking;
      expect(() {
        tracking = Tracking.fromJson({
          'completions': [
            {'key': 'purchase', 'url': 'https://t/ok'}, // valid
            {'key': 'no_url'}, // missing url → dropped
            {'url': 'https://t/no_key'}, // missing key → dropped
            {'key': 1, 'url': 2}, // retyped → dropped
            'not-a-map', // wrong shape → dropped
          ],
        });
      }, returnsNormally);

      expect(tracking.completions!.length, equals(1));
      expect(tracking.getCompletionUrl(key: 'purchase'), equals('https://t/ok'));
    });

    test('completions as wrong type (not a list) → null, no throw', () {
      late Tracking tracking;
      expect(() {
        tracking = Tracking.fromJson({'completions': 'nope'});
      }, returnsNormally);
      expect(tracking.completions, isNull);
    });
  });

  group('fireCompletion + completion modes', () {
    test('custom_event: fireCompletion fires the provided URL once', () async {
      final fired = <String>[];
      final mockClient = MockClient((request) async {
        fired.add(request.url.toString());
        return http.Response('', 200);
      });
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );

      final creative = Creative.fromJson({
        'contents': [
          {'key': 'h', 'value': 'x', 'type': 'text'}
        ],
        'advertiser': {'name': 'Acme'},
        'template': {'key': 'native'},
        'tracking': {
          'impressions': [
            {'key': 'default', 'url': 'https://t.example/v1/tracking?e=imp'}
          ],
          'completions': [
            {'key': 'purchase', 'url': 'https://t.example/v1/tracking?e=cmp'}
          ],
        },
        'journey': {'dealId': 'jad_1', 'isCompletion': false},
      });

      expect(creative.hasCompletionUrl, isTrue);
      expect(creative.isJourneyCompletion, isFalse);

      sdk.fireCompletion(creative.tracking, key: 'purchase');
      await Future.delayed(Duration.zero);

      expect(fired, equals(['https://t.example/v1/tracking?e=cmp']));
    });

    test('final_stage: no completion URL, nothing extra fired', () async {
      final fired = <String>[];
      final mockClient = MockClient((request) async {
        fired.add(request.url.toString());
        return http.Response('', 200);
      });
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );

      final creative = Creative.fromJson({
        'contents': [
          {'key': 'h', 'value': 'x', 'type': 'text'}
        ],
        'advertiser': {'name': 'Acme'},
        'template': {'key': 'native'},
        'tracking': {
          'impressions': [
            {'key': 'default', 'url': 'https://t.example/v1/tracking?e=imp'}
          ],
          // no completions array
        },
        'journey': {'dealId': 'jad_1', 'isCompletion': true},
      });

      expect(creative.isJourneyCompletion, isTrue);
      expect(creative.hasCompletionUrl, isFalse);

      // Attempting fireCompletion is a safe no-op (no URL to fire).
      sdk.fireCompletion(creative.tracking, key: 'anything');
      // The normal impression is what the publisher fires.
      sdk.fireImpression(creative.tracking);
      await Future.delayed(Duration.zero);

      expect(fired, equals(['https://t.example/v1/tracking?e=imp']));
    });
  });

  group('fireCompletion key-miss is not silent for billing', () {
    test('non-empty completions but wrong key → warns, fires nothing',
        () async {
      final records = <LogRecord>[];
      final logger = Logger('jt-firecmp')
        ..level = Level.ALL
        ..onRecord.listen(records.add);
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01', logger: logger),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      final tracking = trackingWith(completions: [
        {'key': 'purchase', 'url': 'https://t/cmp'},
      ]);
      sdk.fireCompletion(tracking, key: 'wrong_key');
      await Future.delayed(Duration.zero);

      expect(fired, isEmpty);
      expect(
        records.where((r) =>
            r.level >= Level.WARNING && r.message.contains('wrong_key')),
        isNotEmpty,
      );
    });

    test('no completions (final_stage) → no warning, no fire', () async {
      final records = <LogRecord>[];
      final logger = Logger('jt-firecmp-final')
        ..level = Level.ALL
        ..onRecord.listen(records.add);
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01', logger: logger),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      sdk.fireCompletion(trackingWith(), key: 'anything');
      await Future.delayed(Duration.zero);

      expect(fired, isEmpty);
      expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
    });
  });

  group('URLs fired verbatim', () {
    test('opaque tracking URL is not modified', () async {
      final fired = <String>[];
      final mockClient = MockClient((request) async {
        fired.add(request.url.toString());
        return http.Response('', 200);
      });
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
        httpClient: mockClient,
      );

      const opaque =
          'https://t.example/v1/tracking?e=AbC123.dEf456-_garbagetoken';
      sdk.fireTracking(opaque);
      await Future.delayed(Duration.zero);

      expect(fired, equals([opaque]));
    });
  });

  group('fireTracking is null-safe on malformed URLs', () {
    test('a URL Uri.tryParse rejects → warns, no throw, nothing fired',
        () async {
      final records = <LogRecord>[];
      final logger = Logger('jt-badurl')
        ..level = Level.ALL
        ..onRecord.listen(records.add);
      final fired = <String>[];
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: baseUrl, logger: logger),
        httpClient: MockClient((r) async {
          fired.add(r.url.toString());
          return http.Response('', 200);
        }),
      );

      // Malformed / schemeless inputs must not crash the guard.
      for (final bad in const ['::::', 'not a url', 'ftp-no-scheme', '']) {
        expect(() => sdk.fireTracking(bad), returnsNormally);
      }
      await Future.delayed(Duration.zero);

      expect(fired, isEmpty);
      expect(records.where((r) => r.level >= Level.WARNING), isNotEmpty);
    });
  });
}
