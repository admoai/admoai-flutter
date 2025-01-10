import 'package:flutter_test/flutter_test.dart';
import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';

const baseUrl = 'https://mock.api.admoai.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AdMoai sdk;

  setUp(() async {
    // Mock the timezone platform channel
    const MethodChannel channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getLocalTimezone') {
          return 'UTC';
        }
        return null;
      },
    );

    final config = SDKConfig(baseUrl: baseUrl);
    sdk = await AdMoai.initialize(config: config);
  });

  group('Basic Request Builder Tests', () {
    test('testBasicRequestBuilder', () {
      final builder = sdk.createRequestBuilder();
      final request = builder
          .addPlacement(key: 'home', count: 2)
          .addGeoTargeting(5819)
          .addLocationTargeting(latitude: 40.7128, longitude: -74.0060) // NYC
          .addLocationTargeting(latitude: 51.5074, longitude: -0.1278) // London
          .setUserId('user123')
          .setUserIp('192.168.1.1')
          .build();

      // Verify basic request structure
      expect(request.placements.length, equals(1));
      expect(request.placements.first.key, equals('home'));
      expect(request.placements.first.count, equals(2));
      expect(request.targeting?.geo?.contains(5819), isTrue);
      expect(request.targeting?.location?.length, equals(2));
      expect(request.targeting?.location?.first.latitude, equals(40.7128));
      expect(request.targeting?.location?.first.longitude, equals(-74.0060));
      expect(request.targeting?.location?.last.latitude, equals(51.5074));
      expect(request.targeting?.location?.last.longitude, equals(-0.1278));
      expect(request.user?.id, equals('user123'));
      expect(request.user?.ip, equals('192.168.1.1'));
    });
  });

  group('Location Targeting Tests', () {
    test('testLocationTargeting', () {
      final builder = sdk.createRequestBuilder();
      var request = builder
          .addLocationTargeting(latitude: 40.7128, longitude: -74.0060) // NYC
          .addLocationTargeting(latitude: 51.5074, longitude: -0.1278) // London
          .addLocationTargeting(latitude: 48.8566, longitude: 2.3522) // Paris
          .build();

      expect(request.targeting?.location?.length, equals(3));

      // Verify each location exists
      expect(
          request.targeting?.location?.any((coord) =>
              coord.latitude == 40.7128 && coord.longitude == -74.0060),
          isTrue,
          reason: 'NYC coordinates not found');

      expect(
          request.targeting?.location?.any((coord) =>
              coord.latitude == 51.5074 && coord.longitude == -0.1278),
          isTrue,
          reason: 'London coordinates not found');

      expect(
          request.targeting?.location?.any((coord) =>
              coord.latitude == 48.8566 && coord.longitude == 2.3522),
          isTrue,
          reason: 'Paris coordinates not found');
    });

    test('testLocationTargetingUniqueness', () {
      final builder = sdk.createRequestBuilder();
      var request = builder
          .addLocationTargeting(latitude: 40.7128, longitude: -74.0060) // NYC
          .addLocationTargeting(latitude: 51.5074, longitude: -0.1278) // London
          .addLocationTargeting(
              latitude: 40.7128, longitude: -74.0060) // NYC (duplicate)
          .addLocationTargeting(latitude: 48.8566, longitude: 2.3522) // Paris
          .build();

      expect(request.targeting?.location?.length, equals(3));

      final nycCount = request.targeting?.location
          ?.where((coord) =>
              coord.latitude == 40.7128 && coord.longitude == -74.0060)
          .length;
      expect(nycCount, equals(1), reason: 'Expected one occurrence of NYC');
    });
  });

  group('Custom Targeting Tests', () {
    test('testCustomTargeting', () {
      final builder = sdk.createRequestBuilder();
      final request = builder
          .addCustomTargeting(key: 'age', value: 25)
          .addCustomTargeting(key: 'score', value: 98.6)
          .addCustomTargeting(key: 'name', value: 'John')
          .addCustomTargeting(key: 'premium', value: true)
          .build();

      expect(request.targeting?.custom?.length, equals(4));
      expect(
          request.targeting?.custom
              ?.any((kv) => kv.key == 'age' && kv.value as int == 25),
          isTrue);
      expect(
          request.targeting?.custom
              ?.any((kv) => kv.key == 'score' && kv.value as double == 98.6),
          isTrue);
    });

    test('testCustomTargetingUniqueness', () {
      final builder = sdk.createRequestBuilder();
      final request = builder
          .addCustomTargeting(key: 'category', value: 'sports')
          .addCustomTargeting(key: 'category', value: 'news') // Should override
          .build();

      expect(request.targeting?.custom?.length, equals(1));
      expect(
          request.targeting?.custom
              ?.any((kv) => kv.key == 'category' && kv.value == 'news'),
          isTrue);
      expect(
          request.targeting?.custom
              ?.any((kv) => kv.key == 'category' && kv.value == 'sports'),
          isFalse);
    });
  });

  group('Clearing Operations Tests', () {
    test('testClearingOperations', () {
      final builder = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .addGeoTargeting(5819)
          .addLocationTargeting(latitude: 40.7128, longitude: -74.0060)
          .addCustomTargeting(key: 'category', value: 'news')
          .setUserId('user123');

      var request = builder.clearPlacements().build();
      expect(request.placements.isEmpty, isTrue);
      expect(request.targeting?.geo?.isEmpty, isFalse);

      request = builder.clearTargeting().build();
      expect(request.targeting, isNull);
      expect(request.user, isNotNull);

      request = builder.clearUser().build();
      expect(request.user, isNull);

      request = builder.clearAll().build();
      expect(request.placements.isEmpty, isTrue);
      expect(request.targeting, isNull);
      expect(request.user, isNull);
      expect(request.device, isNull);
      expect(request.app, isNull);
    });
  });
}
