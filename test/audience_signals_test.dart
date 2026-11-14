import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/models/audience_signals.dart' show normalizeCarrier;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DecisionRequestBuilder _builder({DeviceConfig? device}) {
  return DecisionRequestBuilder(
    appConfig: AppConfig(name: 'Demo'),
    deviceConfig: device ?? DeviceConfig(id: 'd1', model: 'M'),
    userConfig: UserConfig(id: 'u1'),
  )..addPlacement(key: 'home');
}

Map<String, dynamic> _json(DecisionRequestBuilder b) =>
    jsonDecode(jsonEncode(b.build().toJson())) as Map<String, dynamic>;

List<dynamic> _custom(DecisionRequestBuilder b) =>
    (_json(b)['targeting']['custom'] as List).cast<dynamic>();

dynamic _valueOf(DecisionRequestBuilder b, String key) {
  final matches = _custom(b).where((e) => e['key'] == key).toList();
  expect(matches, hasLength(1), reason: 'key $key must appear exactly once');
  return matches.single['value'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('enum wire values', () {
    final tables = <String, (List<Enum>, List<String>)>{
      'AgeGroup': (
        AgeGroup.values,
        ['under_18', '18_24', '25_34', '35_44', '45_54', '55_64', '65_plus']
      ),
      'Gender': (
        Gender.values,
        ['female', 'male', 'other', 'prefer_not_to_say']
      ),
      'AccountType': (
        AccountType.values,
        ['personal', 'business', 'family', 'student', 'other']
      ),
      'SubscriptionStatus': (
        SubscriptionStatus.values,
        ['none', 'trial', 'active', 'paused', 'expired']
      ),
      'AccountTenure': (
        AccountTenure.values,
        ['0_30d', '31_90d', '91_365d', '366d_plus']
      ),
      'TripFrequency30d': (
        TripFrequency30d.values,
        ['0', '1_2', '3_9', '10_plus']
      ),
      'LastTripRecency': (
        LastTripRecency.values,
        ['never', '0_7d', '8_30d', '31_90d', '91d_plus']
      ),
      'DeviceCategory': (DeviceCategory.values, ['phone', 'tablet', 'other']),
    };

    String wire(Enum e) => (e as dynamic).value as String;

    tables.forEach((name, table) {
      test('$name has exactly the catalog values, in order', () {
        expect(table.$1.map(wire).toList(), table.$2);
      });
    });

    test('key constants', () {
      expect(AudienceSignalKey.ageGroup, 'age_group');
      expect(AudienceSignalKey.gender, 'gender');
      expect(AudienceSignalKey.accountType, 'account_type');
      expect(AudienceSignalKey.subscriptionStatus, 'subscription_status');
      expect(AudienceSignalKey.accountTenure, 'account_tenure');
      expect(AudienceSignalKey.tripFrequency30d, 'trip_frequency_30d');
      expect(AudienceSignalKey.lastTripRecency, 'last_trip_recency');
      expect(AudienceSignalKey.publisherSegments, 'publisher_segments');
    });

    final setters = <String,
        (
      String,
      List<Enum>,
      DecisionRequestBuilder Function(DecisionRequestBuilder, Enum)
    )>{
      'setAgeGroup': (
        'age_group',
        AgeGroup.values,
        (b, e) => b.setAgeGroup(e as AgeGroup)
      ),
      'setGender': (
        'gender',
        Gender.values,
        (b, e) => b.setGender(e as Gender)
      ),
      'setAccountType': (
        'account_type',
        AccountType.values,
        (b, e) => b.setAccountType(e as AccountType)
      ),
      'setSubscriptionStatus': (
        'subscription_status',
        SubscriptionStatus.values,
        (b, e) => b.setSubscriptionStatus(e as SubscriptionStatus)
      ),
      'setAccountTenure': (
        'account_tenure',
        AccountTenure.values,
        (b, e) => b.setAccountTenure(e as AccountTenure)
      ),
      'setTripFrequency30d': (
        'trip_frequency_30d',
        TripFrequency30d.values,
        (b, e) => b.setTripFrequency30d(e as TripFrequency30d)
      ),
      'setLastTripRecency': (
        'last_trip_recency',
        LastTripRecency.values,
        (b, e) => b.setLastTripRecency(e as LastTripRecency)
      ),
    };

    setters.forEach((name, s) {
      test('$name serializes every member as a single string entry', () {
        for (final member in s.$2) {
          final b = s.$3(_builder(), member);
          expect(_valueOf(b, s.$1), wire(member));
          expect(_valueOf(b, s.$1), isA<String>());
        }
      });
    });

    test('"0" is a JSON string', () {
      final b = _builder().setTripFrequency30d(TripFrequency30d.zero);
      expect(jsonEncode(_json(b)['targeting']),
          '{"custom":[{"key":"trip_frequency_30d","value":"0"}]}');
    });
  });

  group('publisher segments', () {
    test('one code is a one-element array', () {
      final b = _builder().setPublisherSegments(['high_value']);
      expect(_valueOf(b, 'publisher_segments'), ['high_value']);
    });

    test('many codes keep order', () {
      final b = _builder().setPublisherSegments(['b', 'a', 'C']);
      expect(_valueOf(b, 'publisher_segments'), ['b', 'a', 'C']);
    });

    test('duplicates are removed in first-occurrence order', () {
      final b = _builder().setPublisherSegments(
          ['airport_commuter', 'high_value', 'airport_commuter']);
      expect(_valueOf(b, 'publisher_segments'),
          ['airport_commuter', 'high_value']);
    });

    test('empty list removes an earlier value', () {
      final b = _builder()
          .setPublisherSegments(['high_value'])
          .addCustomTargeting(key: 'other', value: 1)
          .setPublisherSegments([]);
      expect(_custom(b), [
        {'key': 'other', 'value': 1}
      ]);
    });

    test('emptying the only custom entry restores the untargeted wire', () {
      final b = _builder()
          .setPublisherSegments(['high_value']).setPublisherSegments([]);
      expect(_json(b), _json(_builder()));
    });

    test(
        'emptying the only custom entry keeps other targeting without "custom"',
        () {
      final b = _builder()
          .addGeoTargeting(2643743)
          .setPublisherSegments(['high_value']).setPublisherSegments([]);
      final targeting = _json(b)['targeting'] as Map<String, dynamic>;
      expect(targeting.containsKey('custom'), isFalse);
      expect(targeting['geo'], [2643743]);
    });

    test('empty list on a fresh builder adds nothing', () {
      final b = _builder().setPublisherSegments([]);
      expect(_json(b).containsKey('targeting'), isFalse);
    });

    for (final bad in [' high_value', '', 'high-value', 'café']) {
      test('invalid code "$bad" throws and leaves the builder unchanged', () {
        final b = _builder().setPublisherSegments(['high_value']);
        expect(
          () => b.setPublisherSegments(['ok', bad]),
          throwsA(isA<ArgumentError>()
              .having((e) => e.toString(), 'message', contains('"$bad"'))),
        );
        expect(_valueOf(b, 'publisher_segments'), ['high_value']);
      });
    }

    test('unknown or archived-looking codes and case pass through', () {
      final b = _builder().setPublisherSegments(['ARCHIVED_old', 'Zz_9']);
      expect(_valueOf(b, 'publisher_segments'), ['ARCHIVED_old', 'Zz_9']);
    });

    test('stored list is unmodifiable and independent of the input', () {
      final input = ['a'];
      final b = _builder().setPublisherSegments(input);
      input.add('b');
      expect(_valueOf(b, 'publisher_segments'), ['a']);
    });
  });

  group('null removes a key', () {
    final removers = <String,
        (
      String,
      DecisionRequestBuilder Function(DecisionRequestBuilder),
      DecisionRequestBuilder Function(DecisionRequestBuilder)
    )>{
      'setAgeGroup': (
        'age_group',
        (b) => b.setAgeGroup(AgeGroup.age25To34),
        (b) => b.setAgeGroup(null)
      ),
      'setGender': (
        'gender',
        (b) => b.setGender(Gender.male),
        (b) => b.setGender(null)
      ),
      'setAccountType': (
        'account_type',
        (b) => b.setAccountType(AccountType.business),
        (b) => b.setAccountType(null)
      ),
      'setSubscriptionStatus': (
        'subscription_status',
        (b) => b.setSubscriptionStatus(SubscriptionStatus.active),
        (b) => b.setSubscriptionStatus(null)
      ),
      'setAccountTenure': (
        'account_tenure',
        (b) => b.setAccountTenure(AccountTenure.days0To30),
        (b) => b.setAccountTenure(null)
      ),
      'setTripFrequency30d': (
        'trip_frequency_30d',
        (b) => b.setTripFrequency30d(TripFrequency30d.trips3To9),
        (b) => b.setTripFrequency30d(null)
      ),
      'setLastTripRecency': (
        'last_trip_recency',
        (b) => b.setLastTripRecency(LastTripRecency.days0To7),
        (b) => b.setLastTripRecency(null)
      ),
      'setPublisherSegments': (
        'publisher_segments',
        (b) => b.setPublisherSegments(['a', 'b']),
        (b) => b.setPublisherSegments(null)
      ),
    };

    removers.forEach((name, r) {
      final (key, set, clear) = r;

      test('$name(null) removes only its own key, keeping the others in order',
          () {
        final b = _builder().addCustomTargeting(key: 'a', value: 1);
        set(b);
        b.addCustomTargeting(key: 'z', value: 2);
        clear(b);
        expect(_custom(b).map((e) => e['key']).toList(), ['a', 'z']);
        expect(_valueOf(b, 'a'), 1);
        expect(_valueOf(b, 'z'), 2);
      });

      test('$name(null) after the only entry restores the untargeted wire', () {
        final b = clear(set(_builder()));
        expect(_json(b), _json(_builder()));
      });

      test('$name(null) keeps other targeting axes without "custom"', () {
        final b = clear(set(_builder().addGeoTargeting(2643743)));
        final targeting = _json(b)['targeting'] as Map<String, dynamic>;
        expect(targeting.containsKey('custom'), isFalse);
        expect(targeting['geo'], [2643743]);
      });

      test('$name(null) on a fresh builder equals an untargeted builder', () {
        expect(_json(clear(_builder())), _json(_builder()));
      });

      test('$name(null) when the key is absent leaves other entries alone', () {
        final b = clear(_builder().addCustomTargeting(key: 'a', value: 1));
        expect(_custom(b), [
          {'key': 'a', 'value': 1}
        ]);
      });
    });
  });

  group('last write wins per key', () {
    test('typed then generic', () {
      final b = _builder()
          .setGender(Gender.male)
          .addCustomTargeting(key: 'gender', value: 'female');
      expect(_valueOf(b, 'gender'), 'female');
    });

    test('generic then typed', () {
      final b = _builder()
          .addCustomTargeting(key: 'gender', value: 'female')
          .setGender(Gender.male);
      expect(_valueOf(b, 'gender'), 'male');
    });

    test('other keys are preserved and their order is unchanged', () {
      final b = _builder()
          .addCustomTargeting(key: 'a', value: 1)
          .setAgeGroup(AgeGroup.age25To34)
          .addCustomTargeting(key: 'b', value: 2)
          .setGender(Gender.other);
      expect(_custom(b).map((e) => e['key']).toList(),
          ['a', 'age_group', 'b', 'gender']);
      b.setAgeGroup(AgeGroup.age35To44);
      expect(_custom(b).map((e) => e['key']).toList(),
          ['a', 'b', 'gender', 'age_group']);
      expect(_valueOf(b, 'a'), 1);
      expect(_valueOf(b, 'b'), 2);
    });
  });

  group('device carrier and category', () {
    test('set values are present after existing keys', () {
      final b = _builder(
        device: DeviceConfig(
          id: 'd1',
          language: 'en',
          carrier: 'Example Mobile',
          category: DeviceCategory.tablet,
        ),
      );
      expect(jsonEncode(_json(b)['device']),
          '{"id":"d1","language":"en","carrier":"Example Mobile","category":"tablet"}');
    });

    test('unset values are absent', () {
      final device = _json(_builder())['device'] as Map<String, dynamic>;
      expect(device.containsKey('carrier'), isFalse);
      expect(device.containsKey('category'), isFalse);
    });

    test('normalizeCarrier', () {
      expect(normalizeCarrier('  Example Mobile  '), 'Example Mobile');
      expect(normalizeCarrier(null), isNull);
      for (final raw in ['WiFi', 'Wi-Fi', 'wifi', '--', 'Unknown', '   ', '']) {
        expect(normalizeCarrier(raw), isNull, reason: raw);
      }
      expect(normalizeCarrier('Unknown Telecom'), 'Unknown Telecom');
    });

    test('Device normalizes carrier when built directly', () {
      expect(Device(carrier: 'wifi').toJson().containsKey('carrier'), isFalse);
      expect(Device(carrier: ' Example Mobile ').toJson()['carrier'],
          'Example Mobile');
    });

    test('DeviceConfig normalizes carrier', () {
      expect(DeviceConfig(carrier: '  X  ').carrier, 'X');
      expect(DeviceConfig(carrier: 'WiFi').carrier, isNull);
      final b = _builder(device: DeviceConfig(id: 'd1', carrier: '   '));
      expect((_json(b)['device'] as Map).containsKey('carrier'), isFalse);
    });

    group('AdMoai config', () {
      late AdMoai sdk;

      setUp(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'UTC' : null,
        );
        sdk = await AdMoai.initialize(
            config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'));
      });

      Map<String, dynamic> device() =>
          _json(sdk.createRequestBuilder()..addPlacement(key: 'p'))['device']
              as Map<String, dynamic>;

      test('setDeviceConfig merges over current values', () {
        sdk.setDeviceConfig(carrier: 'Example Mobile');
        sdk.setDeviceConfig(category: DeviceCategory.phone);
        expect(device()['carrier'], 'Example Mobile');
        expect(device()['category'], 'phone');
        sdk.setDeviceConfig(model: 'X');
        expect(device()['carrier'], 'Example Mobile');
        expect(device()['category'], 'phone');
      });

      test('setDeviceConfig normalizes carrier', () {
        sdk.setDeviceConfig(carrier: ' Wi-Fi ');
        expect(sdk.deviceConfig.carrier, isNull);
      });

      test('clearDeviceConfig clears them', () {
        sdk.setDeviceConfig(
            carrier: 'Example Mobile', category: DeviceCategory.tablet);
        sdk.clearDeviceConfig();
        expect(sdk.deviceConfig.carrier, isNull);
        expect(sdk.deviceConfig.category, isNull);
      });
    });

    test('disableDeviceCollection omits the whole device', () {
      final b = _builder(
        device: DeviceConfig(
            id: 'd1',
            carrier: 'Example Mobile',
            category: DeviceCategory.phone),
      ).disableDeviceCollection();
      final json = _json(b);
      expect(json.containsKey('device'), isFalse);
      expect(jsonEncode(json), isNot(contains('Example Mobile')));
      expect(jsonEncode(json), isNot(contains('category')));
    });
  });
}
