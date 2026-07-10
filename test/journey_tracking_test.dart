import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
}
