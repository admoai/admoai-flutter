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

  group('Format Tests', () {
    test('Format enum exposes both native and video', () {
      expect(Format.native.value, equals('native'));
      expect(Format.video.value, equals('video'));
    });

    test('placement with Format.video serializes "format": "video"', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home', format: Format.video)
          .build();

      expect(request.placements.first.format, equals(Format.video));
      final json = request.toJson();
      final placementsJson = json['placements'] as List;
      expect((placementsJson.first as Map)['format'], equals('video'));
    });

    test('placement with Format.native serializes "format": "native"', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home', format: Format.native)
          .build();

      final json = request.toJson();
      final placementsJson = json['placements'] as List;
      expect((placementsJson.first as Map)['format'], equals('native'));
    });

    test('placement without explicit format omits the field', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .build();

      final json = request.toJson();
      final placementsJson = json['placements'] as List;
      expect((placementsJson.first as Map).containsKey('format'), isFalse);
    });

    test('mixed Format placements coexist in one request', () {
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'native_slot', format: Format.native)
          .addPlacement(key: 'video_slot', format: Format.video)
          .build();

      expect(request.placements.length, equals(2));
      expect(request.placements[0].format, equals(Format.native));
      expect(request.placements[1].format, equals(Format.video));
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

  group('Destination Targeting Tests', () {
    test('single destination is added and serialized correctly', () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 40.7128, longitude: -74.0060, minConfidence: 0.8)
          .build();

      expect(request.targeting?.destination?.length, equals(1));
      final first = request.targeting!.destination!.first;
      expect(first.latitude, equals(40.7128));
      expect(first.longitude, equals(-74.0060));
      expect(first.minConfidence, equals(0.8));

      final json = request.toJson();
      final targetingJson = json['targeting'] as Map<String, dynamic>;
      final destList = targetingJson['destination'] as List;
      expect(destList.length, equals(1));
      expect((destList.first as Map)['latitude'], equals(40.7128));
      expect((destList.first as Map)['longitude'], equals(-74.0060));
      expect((destList.first as Map)['min_confidence'], equals(0.8));
    });

    test('duplicate destinations are deduplicated', () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 40.7128, longitude: -74.0060, minConfidence: 0.8)
          .addDestinationTargeting(
              latitude: 40.7128, longitude: -74.0060, minConfidence: 0.8)
          .addDestinationTargeting(
              latitude: 51.5074, longitude: -0.1278, minConfidence: 0.9)
          .build();

      expect(request.targeting?.destination?.length, equals(2));
    });

    test('destinations with same coords but different minConfidence are kept',
        () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 40.7128, longitude: -74.0060, minConfidence: 0.5)
          .addDestinationTargeting(
              latitude: 40.7128, longitude: -74.0060, minConfidence: 0.9)
          .build();

      expect(request.targeting?.destination?.length, equals(2));
    });

    test('setDestinationTargeting replaces existing destinations', () {
      final destA = Destination(
          latitude: 1, longitude: 2, minConfidence: 0.5);
      final destB = Destination(
          latitude: 3, longitude: 4, minConfidence: 0.7);

      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 99, longitude: 99, minConfidence: 0.1)
          .setDestinationTargeting([destA, destB])
          .build();

      expect(request.targeting?.destination?.length, equals(2));
      expect(request.targeting?.destination?.first.latitude, equals(1));
      expect(request.targeting?.destination?.last.latitude, equals(3));
    });

    test('clearDestinationTargeting removes all destinations', () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 1, longitude: 2, minConfidence: 0.5)
          .addGeoTargeting(5819)
          .clearDestinationTargeting()
          .build();

      expect(request.targeting?.destination, isNull);
      expect(request.targeting?.geo?.contains(5819), isTrue);
    });

    test('clearTargeting removes destinations', () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 1, longitude: 2, minConfidence: 0.5)
          .clearTargeting()
          .build();

      expect(request.targeting, isNull);
    });

    test('minConfidence above 1.0 throws ArgumentError', () {
      final builder = sdk.createRequestBuilder();
      expect(
        () => builder.addDestinationTargeting(
            latitude: 0, longitude: 0, minConfidence: 1.5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('minConfidence below 0.0 throws ArgumentError', () {
      final builder = sdk.createRequestBuilder();
      expect(
        () => builder.addDestinationTargeting(
            latitude: 0, longitude: 0, minConfidence: -0.1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('minConfidence at 0.0 and 1.0 boundaries is accepted', () {
      final request = sdk
          .createRequestBuilder()
          .addDestinationTargeting(
              latitude: 1, longitude: 2, minConfidence: 0.0)
          .addDestinationTargeting(
              latitude: 3, longitude: 4, minConfidence: 1.0)
          .build();

      expect(request.targeting?.destination?.length, equals(2));
    });

    test('destination coexists with other targeting fields', () {
      final request = sdk
          .createRequestBuilder()
          .addGeoTargeting(5819)
          .addLocationTargeting(latitude: 10, longitude: 20)
          .addDestinationTargeting(
              latitude: 30, longitude: 40, minConfidence: 0.5)
          .addCustomTargeting(key: 'k', value: 'v')
          .build();

      expect(request.targeting?.geo?.length, equals(1));
      expect(request.targeting?.location?.length, equals(1));
      expect(request.targeting?.destination?.length, equals(1));
      expect(request.targeting?.custom?.length, equals(1));
    });
  });
}
