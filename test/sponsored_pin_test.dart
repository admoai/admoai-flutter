import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Sponsored Pin Locations — distance requests, Matched Point models, point tracking.
///
/// Spec: adhub `features/sponsored-pin-locations/specs/E11-sdk.md`. Test names reference its
/// acceptance-criteria numbers, the way `third_party_tracker_test.dart` references E06's parity
/// matrix. Mirrors the iOS reference suite (`SponsoredPinTests.swift`).
///
/// AC8c (no bulk tap or click exists) has no test: the absence of an API is not observable at
/// runtime, so it is a review item.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AdMoai, List<http.Request>)> sdkWithCapture() async {
    final captured = <http.Request>[];
    final client = MockClient((request) async {
      captured.add(request);
      return http.Response('', 200);
    });
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
        baseUrl: 'https://mock.api.admoai.com',
        apiVersion: '2025-11-01',
        defaultLanguage: 'en',
      ),
      httpClient: client,
    );
    return (sdk, captured);
  }

  /// The unawaited fire-and-forget futures need event-loop turns to complete.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> firedUrls(List<http.Request> captured) =>
      captured.map((r) => r.url.toString()).toList();

  /// The builder needs the app/device/user config the SDK assembles, so it comes from an
  /// instance rather than being constructed directly — the same way `admoai_test.dart` does it.
  Future<DecisionRequestBuilder> builder() async {
    final (sdk, _) = await sdkWithCapture();
    return sdk.createRequestBuilder()..addPlacement(key: 'map');
  }

  Creative creative(List<dynamic> contents) => Creative.fromJson({
        'contents': contents,
        'advertiser': {'name': 'Cabify'},
        'tracking': {
          'impressions': [
            {'key': 'default', 'url': 'https://t.example/imp'}
          ],
          'clicks': [
            {'key': 'default', 'url': 'https://t.example/click'}
          ],
        },
      });

  List<dynamic> pointsContent(List<Map<String, dynamic>> points) => [
        {
          'key': 'matched_points',
          'type': 'matched_points',
          'value': points,
        }
      ];

  Map<String, dynamic> trackedPoint(String id, String path) => {
        'id': id,
        'name': id,
        'latitude': 1.0,
        'longitude': 2.0,
        'distance': 10,
        'tracking': {
          'views': [
            {'key': 'default', 'url': 'https://t.example/$path/view'}
          ],
          'taps': [
            {'key': 'default', 'url': 'https://t.example/$path/tap'}
          ],
          'clicks': [
            {'key': 'default', 'url': 'https://t.example/$path/click'}
          ],
        },
      };

  group('request side', () {
    test('AC1 - radius search serializes', () async {
      final request = (await builder())
          .setDistanceTargeting(Distance.radius(
            latitude: -33.4175,
            longitude: -70.6065,
            radiusMeters: 8000,
          ))
          .build();
      final json = request.toJson()['targeting'] as Map<String, dynamic>;
      final distance = json['distance'] as Map<String, dynamic>;

      expect(distance['radius'], 8000);
      expect(distance['latitude'], -33.4175);
      expect(distance.containsKey('bounds'), isFalse);
    });

    test('AC1 - bounds search serializes and keeps the origin', () async {
      final request = (await builder())
          .setDistanceTargeting(Distance.bounds(
            latitude: -33.4175,
            longitude: -70.6065,
            bounds: const DistanceBounds(
                north: -33.38, south: -33.46, east: -70.54, west: -70.68),
          ))
          .build();
      final distance = (request.toJson()['targeting']
          as Map<String, dynamic>)['distance'] as Map<String, dynamic>;

      expect(distance['bounds'], isNotNull);
      // "Nearest first" needs an origin, and the centre of a box is not necessarily the viewer.
      expect(distance['latitude'], -33.4175);
      expect(distance.containsKey('radius'), isFalse);
    });

    test('AC4 - limit is emitted only when given', () async {
      final withLimit = (await builder())
          .setDistanceTargeting(Distance.radius(
              latitude: 0, longitude: 0, radiusMeters: 500, limit: 5))
          .build();
      final without = (await builder())
          .setDistanceTargeting(
              Distance.radius(latitude: 0, longitude: 0, radiusMeters: 500))
          .build();

      expect(
        ((withLimit.toJson()['targeting'] as Map<String, dynamic>)['distance']
            as Map<String, dynamic>)['limit'],
        5,
      );
      expect(
        ((without.toJson()['targeting'] as Map<String, dynamic>)['distance']
                as Map<String, dynamic>)
            .containsKey('limit'),
        isFalse,
      );
    });

    test('AC5 - no distance key when never set', () async {
      final request = (await builder()).setGeoTargeting([123]).build();
      final targeting = request.toJson()['targeting'] as Map<String, dynamic>;

      expect(targeting.containsKey('distance'), isFalse);
    });

    test('AC2 - refuses an impossible origin', () {
      expect(
        () => Distance.radius(latitude: 91, longitude: 0, radiusMeters: 100),
        throwsArgumentError,
      );
      expect(
        () => Distance.radius(latitude: 0, longitude: -181, radiusMeters: 100),
        throwsArgumentError,
      );
    });

    test('AC2 - refuses a non-positive radius', () {
      expect(
        () => Distance.radius(latitude: 0, longitude: 0, radiusMeters: 0),
        throwsArgumentError,
      );
    });

    test('AC2 - refuses inverted bounds', () {
      expect(
        () => Distance.bounds(
          latitude: 0,
          longitude: 0,
          bounds: const DistanceBounds(
              north: -33.46, south: -33.38, east: -70.54, west: -70.68),
        ),
        throwsArgumentError,
      );
    });

    test('AC2 - refuses antimeridian bounds', () {
      expect(
        () => Distance.bounds(
          latitude: 0,
          longitude: 179,
          bounds: const DistanceBounds(
              north: 10, south: -10, east: -179, west: 179),
        ),
        throwsArgumentError,
      );
    });

    test('AC2 - refuses a non-positive limit', () {
      expect(
        () => Distance.radius(
            latitude: 0, longitude: 0, radiusMeters: 100, limit: 0),
        throwsArgumentError,
      );
    });

    /// AC3 — the SDK hard-codes NO ceiling. 50 km and 100 km are server policy, and a client
    /// that bakes them in refuses what a newer engine would accept.
    test('AC3 - accepts a radius above the server current ceiling', () {
      final distance =
          Distance.radius(latitude: 0, longitude: 0, radiusMeters: 80000);

      expect(distance.radius, 80000);
    });

    test('AC3 - accepts bounds larger than the server current ceiling', () {
      final distance = Distance.bounds(
        latitude: 0,
        longitude: 0,
        bounds: const DistanceBounds(north: 5, south: -5, east: 5, west: -5),
      );

      expect(distance.bounds, isNotNull);
    });

    test('clear removes the search and nothing else', () async {
      final request = (await builder())
          .setDistanceTargeting(
              Distance.radius(latitude: 0, longitude: 0, radiusMeters: 100))
          .setGeoTargeting([42])
          .clearDistanceTargeting()
          .build();
      final targeting = request.toJson()['targeting'] as Map<String, dynamic>;

      expect(targeting.containsKey('distance'), isFalse);
      expect(targeting['geo'], [42]);
    });

    /// The builder copies its targeting on every setter, so each copy has to carry the search
    /// forward — otherwise setting another axis afterwards silently drops it.
    test('another targeting axis does not drop the search', () async {
      final request = (await builder())
          .setDistanceTargeting(Distance.radius(
              latitude: -33.4175, longitude: -70.6065, radiusMeters: 8000))
          .setGeoTargeting([42])
          .addLocationTargeting(latitude: 1, longitude: 2)
          .build();
      final targeting = request.toJson()['targeting'] as Map<String, dynamic>;

      expect((targeting['distance'] as Map<String, dynamic>)['radius'], 8000);
      expect(targeting['geo'], [42]);
    });
  });

  group('response side', () {
    test('AC4 - matched points decode with every field', () {
      final c = creative(pointsContent([
        {
          'id': 'advertiser_location_01ARZ3NDEKTSV4RRFFQ69G5FAV',
          'name': 'Parque Arauco',
          'address': 'Parque Arauco, Santiago',
          'latitude': -33.4030,
          'longitude': -70.5680,
          'distance': 1834,
          'clickUrl': 'https://shop.example/parque-arauco',
          'tracking': {
            'views': [
              {'key': 'default', 'url': 'https://t.example/pin/view'}
            ],
          },
        }
      ]));
      final point = c.matchedPoints.single;

      expect(point.id, 'advertiser_location_01ARZ3NDEKTSV4RRFFQ69G5FAV');
      expect(point.name, 'Parque Arauco');
      expect(point.address, 'Parque Arauco, Santiago');
      expect(point.latitude, -33.4030);
      expect(point.distance, 1834);
      expect(point.clickUrl, 'https://shop.example/parque-arauco');
      expect(point.tracking?.views?.single.url, 'https://t.example/pin/view');
    });

    test('AC5 - creative without matched points is empty', () {
      final c = creative([
        {'key': 'headline', 'type': 'text', 'value': 'Hi'}
      ]);

      expect(c.matchedPoints, isEmpty);
      expect(c.contents, hasLength(1));
    });

    /// AC6 — a Sponsored Pin response stays parseable by code that knows nothing about pins:
    /// the entry decodes as an ordinary content item, as it always did.
    test('AC6 - matched points remain readable as an ordinary content entry',
        () {
      final c = creative(pointsContent([trackedPoint('loc_1', 'a')]));

      expect(c.contents, hasLength(1));
      expect(c.contents.single.key, 'matched_points');
    });

    test('absent address and click url are null', () {
      final c = creative(pointsContent([
        {
          'id': 'loc_1',
          'name': 'Shop',
          'latitude': 1.0,
          'longitude': 2.0,
          'distance': 10,
        }
      ]));
      final point = c.matchedPoints.single;

      expect(point.address, isNull);
      expect(point.clickUrl, isNull);
      expect(point.tracking, isNull);
    });

    test('unknown point fields are ignored', () {
      final c = creative(pointsContent([
        {
          'id': 'loc_1',
          'name': 'Shop',
          'latitude': 1.0,
          'longitude': 2.0,
          'distance': 10,
          'openingHours': '9-5',
        }
      ]));

      expect(c.matchedPoints, hasLength(1));
    });

    test('malformed point is dropped and siblings survive', () {
      final c = creative(pointsContent([
        {
          'id': 'loc_1',
          'name': 'Good',
          'latitude': 1.0,
          'longitude': 2.0,
          'distance': 10
        },
        {'id': 'loc_2'},
        {
          'id': 'loc_3',
          'name': 'Also',
          'latitude': 3.0,
          'longitude': 4.0,
          'distance': 20
        },
      ]));

      expect(c.matchedPoints.map((p) => p.id).toList(), ['loc_1', 'loc_3']);
    });

    /// AC10 — points hang off their creative, so two winning ads cannot be confused.
    test('AC10 - two creatives keep their own points', () {
      final a = creative(pointsContent([trackedPoint('loc_a', 'a')]));
      final b = creative(pointsContent([trackedPoint('loc_b', 'b')]));

      expect(a.matchedPoints.single.id, 'loc_a');
      expect(b.matchedPoints.single.id, 'loc_b');
    });

    /// AC9 — the resolved destination is used verbatim.
    test('AC9 - click url is used verbatim', () {
      final c = creative(pointsContent([
        {
          'id': 'loc_1',
          'name': 'Shop',
          'latitude': 1.0,
          'longitude': 2.0,
          'distance': 10,
          'clickUrl': 'https://shop.example/parque-arauco',
        }
      ]));

      expect(c.matchedPoints.single.clickUrl,
          'https://shop.example/parque-arauco');
    });
  });

  group('point tracking', () {
    test('AC8 - each helper fires its own list', () async {
      final (sdk, captured) = await sdkWithCapture();
      final point =
          creative(pointsContent([trackedPoint('loc_1', 'p')])).matchedPoints.single;

      sdk.trackPointView(point);
      await settle();
      expect(firedUrls(captured), ['https://t.example/p/view']);

      captured.clear();
      sdk.trackPointTap(point);
      await settle();
      expect(firedUrls(captured), ['https://t.example/p/tap']);

      captured.clear();
      sdk.trackPointClick(point);
      await settle();
      expect(firedUrls(captured), ['https://t.example/p/click']);
    });

    /// AC12 — opening a detail card is a tap and never a click. This is the one that costs
    /// money when it is wrong, so it is asserted rather than documented.
    test('AC12 - a tap never fires the click beacon', () async {
      final (sdk, captured) = await sdkWithCapture();
      final point =
          creative(pointsContent([trackedPoint('loc_1', 'p')])).matchedPoints.single;

      sdk.trackPointTap(point);
      await settle();

      expect(firedUrls(captured), isNot(contains('https://t.example/p/click')));
      expect(firedUrls(captured), isNot(contains('https://t.example/click')));
    });

    /// AC8 — the point click replaces the creative click; it never also fires it.
    test('AC8 - point click does not fire the creative click', () async {
      final (sdk, captured) = await sdkWithCapture();
      final point =
          creative(pointsContent([trackedPoint('loc_1', 'p')])).matchedPoints.single;

      sdk.trackPointClick(point);
      await settle();

      expect(firedUrls(captured), ['https://t.example/p/click']);
    });

    test('point without tracking fires nothing', () async {
      final (sdk, captured) = await sdkWithCapture();
      final point = creative(pointsContent([
        {
          'id': 'loc_1',
          'name': 'Shop',
          'latitude': 1.0,
          'longitude': 2.0,
          'distance': 10
        }
      ])).matchedPoints.single;

      sdk.trackPointView(point);
      sdk.trackPointTap(point);
      sdk.trackPointClick(point);
      await settle();

      expect(captured, isEmpty);
    });

    /// AC7 — parsing a response fires nothing.
    test('AC7 - parsing fires nothing', () async {
      final (_, captured) = await sdkWithCapture();

      creative(pointsContent([trackedPoint('loc_1', 'p')]))
          .matchedPoints
          .map((p) => p.id)
          .toList();
      await settle();

      expect(captured, isEmpty);
    });

    test('AC8b - bulk fires one view per point', () async {
      final (sdk, captured) = await sdkWithCapture();
      final points = creative(pointsContent([
        trackedPoint('a', 'a'),
        trackedPoint('b', 'b'),
        trackedPoint('c', 'c'),
      ])).matchedPoints;

      sdk.trackPointViews(points);
      await settle();

      expect(
        firedUrls(captured).toSet(),
        {
          'https://t.example/a/view',
          'https://t.example/b/view',
          'https://t.example/c/view',
        },
      );
    });

    test('AC8b - bulk deduplicates within the invocation', () async {
      final (sdk, captured) = await sdkWithCapture();
      final point =
          creative(pointsContent([trackedPoint('a', 'a')])).matchedPoints.single;

      sdk.trackPointViews([point, point, point]);
      await settle();

      expect(firedUrls(captured), ['https://t.example/a/view']);
    });

    test('AC8b - bulk does not deduplicate across invocations', () async {
      final (sdk, captured) = await sdkWithCapture();
      final point =
          creative(pointsContent([trackedPoint('a', 'a')])).matchedPoints.single;

      sdk.trackPointViews([point]);
      sdk.trackPointViews([point]);
      await settle();

      expect(firedUrls(captured),
          ['https://t.example/a/view', 'https://t.example/a/view']);
    });

    test('AC8b - bulk with no points fires nothing', () async {
      final (sdk, captured) = await sdkWithCapture();

      sdk.trackPointViews([]);
      await settle();

      expect(captured, isEmpty);
    });

    test('AC8b - bulk skips untrackable points without affecting siblings',
        () async {
      final (sdk, captured) = await sdkWithCapture();
      final points = creative(pointsContent([
        trackedPoint('a', 'a'),
        {
          'id': 'silent',
          'name': 'S',
          'latitude': 2.0,
          'longitude': 2.0,
          'distance': 2
        },
      ])).matchedPoints;

      sdk.trackPointViews(points);
      await settle();

      expect(firedUrls(captured), ['https://t.example/a/view']);
    });
  });
}
