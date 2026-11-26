import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:admoai/src/models/interactive_experience.dart'
    show leadGenerationLaunch;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'e2e/journey_e2e_harness.dart';
import 'e2e/manifest_runner.dart';

/// Offline proof that the live runner sends `request.interactiveExperience` through the SDK's
/// opt-in. The three requests are copied verbatim from scenarios IE1, IE2 and IE3 of the published
/// @admoai/sdk-scenarios 4.0.0 (schemaVersion 7). No network: the HTTP client is a mock.
void main() {
  const ie1 = {
    'apiVersion': '2025-11-01',
    'placements': [
      {'key': 'home'}
    ],
    'interactiveExperience': {
      'supported': true,
      'availableAttributeKeys': ['fullName', 'email', 'phone'],
    },
  };
  const ie2 = {
    'apiVersion': '2025-01-01',
    'placements': [
      {'key': 'home'}
    ],
    'interactiveExperience': {
      'supported': true,
      'availableAttributeKeys': ['fullName', 'email', 'phone'],
    },
  };
  const ie3 = {
    'apiVersion': '2025-11-01',
    'placements': [
      {'key': 'home'}
    ],
    'interactiveExperience': {
      'supported': true,
      'availableAttributeKeys': <String>[],
    },
  };

  tearDown(() => AdMoai.secureSurfaceAvailableForTesting = null);

  AdMoai newSdk(String apiVersion) => AdMoai.forTesting(
        config: SDKConfig(
            baseUrl: 'https://mock.api.admoai.com', apiVersion: apiVersion),
        httpClient: MockClient((r) async => http.Response('{}', 200)),
      );

  String bodyFor(Map<String, dynamic> request) {
    final sdk = newSdk(request['apiVersion'] as String);
    applyScenarioInteractiveExperience(sdk, request['interactiveExperience']);
    final builder = sdk.createRequestBuilder();
    for (final p in (request['placements'] as List).cast<Map>()) {
      builder.addPlacement(key: p['key'] as String);
    }
    return sdk.getHttpRequest(builder.build()).body ?? '';
  }

  for (final (name, request) in [('IE1', ie1), ('IE2', ie2), ('IE3', ie3)]) {
    test('$name: the request body carries the scenario interactiveExperience',
        () {
      final entry = {'id': name, 'request': request, 'expect': {}};
      expect(validateScenarioShape(entry), isEmpty);
      final body = bodyFor(request);
      expect(
        _json(body)['interactiveExperience'],
        equals(request['interactiveExperience']),
      );
    });
  }

  test('an unknown attribute key fails with an interpreter error', () {
    final request = {
      ...ie1,
      'interactiveExperience': {
        'supported': true,
        'availableAttributeKeys': ['fullName', 'shoeSize'],
      },
    };
    expect(validateScenarioShape({'id': 'X', 'request': request, 'expect': {}}),
        isNotEmpty);
    expect(() => bodyFor(request), throwsA(isA<StateError>()));
  });

  test('another shape fails too, never silently dropped', () {
    for (final bad in [
      'yes',
      {'supported': 'yes', 'availableAttributeKeys': <String>[]},
      {'supported': true, 'availableAttributeKeys': 'email'},
    ]) {
      expect(
          () => applyScenarioInteractiveExperience(newSdk('2025-11-01'), bad),
          throwsA(isA<StateError>()));
    }
  });

  test('IE5: supported false is a valid claim and sends no opt-in', () {
    final request = {
      'apiVersion': '2025-11-01',
      'placements': [
        {'key': 'home'}
      ],
      'interactiveExperience': {
        'supported': false,
        'availableAttributeKeys': ['fullName'],
      },
    };
    expect(
        validateScenarioShape({'id': 'IE5', 'request': request, 'expect': {}}),
        isEmpty);
    expect(
        _json(bodyFor(request)).containsKey('interactiveExperience'), isFalse);
  });

  test('a request without it sends no interactiveExperience', () {
    final body = bodyFor({
      'apiVersion': '2025-11-01',
      'placements': [
        {'key': 'home'}
      ],
    });
    expect(_json(body).containsKey('interactiveExperience'), isFalse);
  });

  test('schemaVersion 8 is accepted and 9 refused', () {
    expect(() => requireSupportedSchemaVersion(8), returnsNormally);
    expect(() => requireSupportedSchemaVersion(7), returnsNormally);
    expect(() => requireSupportedSchemaVersion(6), returnsNormally);
    expect(() => requireSupportedSchemaVersion(9), throwsStateError);
    try {
      requireSupportedSchemaVersion(9);
    } on StateError catch (e) {
      expect(e.message, contains('expect.creative.interactiveExperience'));
    }
  });

  group('expect.creative.interactiveExperience shape', () {
    List<String> shape(Object? claim) => validateScenarioShape({
          'id': 'X',
          'request': ie1,
          'expect': {
            'creative': {'interactiveExperience': claim}
          },
        });

    test('accepts false and the object', () {
      expect(shape(false), isEmpty);
      expect(
          shape({
            'type': 'lead_generation',
            'prefillAttributeKeys': ['fullName', 'email'],
          }),
          isEmpty);
    });

    test('refuses an unknown key, a non-list, a missing type and true', () {
      expect(
          shape({
            'type': 'lead_generation',
            'prefillAttributeKeys': <String>[],
            'extra': 1,
          }),
          isNotEmpty);
      expect(
          shape({'type': 'lead_generation', 'prefillAttributeKeys': 'email'}),
          isNotEmpty);
      expect(shape({'prefillAttributeKeys': <String>[]}), isNotEmpty);
      expect(shape(true), isNotEmpty);
    });
  });

  group('assertCreative expect.creative.interactiveExperience', () {
    const claim = {
      'type': 'lead_generation',
      'prefillAttributeKeys': ['fullName', 'email'],
    };
    const ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV';

    Creative creativeWith(InteractiveExperience? ie) => Creative(
          contents: [],
          advertiser: Advertiser(name: 'A'),
          tracking: Tracking(),
          interactiveExperience: ie,
        );

    LeadGenerationExperience experience({
      String formId = 'form_$ulid',
      Uri? launchUrl,
      String token = 'token-abc',
      DateTime? expiresAt,
      List<StandardAttributeKey> keys = const [
        StandardAttributeKey.fullName,
        StandardAttributeKey.email,
      ],
    }) =>
        LeadGenerationExperience(
          formId: formId,
          preparedVersionId: 'form_version_$ulid',
          formInstanceId: 'form_instance_$ulid',
          launchUrl:
              launchUrl ?? Uri.parse('https://10.0.0.5:8080/lead/launch'),
          preparationToken: token,
          expiresAt: expiresAt ??
              DateTime.now().toUtc().add(const Duration(minutes: 5)),
          prefillAttributeKeys: keys,
        );

    void run(Object? c, InteractiveExperience? ie,
            {Object? expected = claim}) =>
        assertCreative(
            creativeWith(ie), {'interactiveExperience': expected}, []);

    test('passes on a well-formed descriptor', () {
      expect(() => run(claim, experience()), returnsNormally);
    });

    test('false passes with no descriptor and fails with one', () {
      expect(() => run(null, null, expected: false), returnsNormally);
      expect(() => run(null, experience(), expected: false), throwsStateError);
    });

    test('a missing descriptor fails the object claim', () {
      expect(() => run(null, null), throwsStateError);
    });

    test('an unsupported experience fails naming its type', () {
      expect(
          () => run(null, const UnsupportedInteractiveExperience(type: 'poll')),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('poll'))));
    });

    test('fails on the wrong key order', () {
      expect(
          () => run(
              null,
              experience(keys: const [
                StandardAttributeKey.email,
                StandardAttributeKey.fullName,
              ])),
          throwsStateError);
    });

    test('fails on an http launchUrl', () {
      expect(
          () => run(null,
              experience(launchUrl: Uri.parse('http://127.0.0.1:8080/lead'))),
          throwsStateError);
    });

    test('fails on a launchUrl with a query or a fragment', () {
      expect(
          () => run(null,
              experience(launchUrl: Uri.parse('https://10.0.0.5/lead?x=1'))),
          throwsStateError);
      expect(
          () => run(null,
              experience(launchUrl: Uri.parse('https://10.0.0.5/lead#f'))),
          throwsStateError);
    });

    test('fails on an empty preparation token', () {
      expect(() => run(null, experience(token: '')), throwsStateError);
    });

    test('fails on a malformed formId', () {
      expect(
          () => run(null, experience(formId: 'form_nope')), throwsStateError);
    });

    test('fails on an expiry that is not after the response arrival', () {
      expect(
          () => run(
              null,
              experience(
                  expiresAt: DateTime.now()
                      .toUtc()
                      .subtract(const Duration(minutes: 1)))),
          throwsStateError);
    });

    test('expiry is judged against the given arrival time', () {
      final expiry = DateTime.utc(2030, 1, 1);
      expect(
          () => assertCreative(creativeWith(experience(expiresAt: expiry)),
              {'interactiveExperience': claim}, [],
              responseReceivedAt: DateTime.utc(2030, 1, 2)),
          throwsStateError);
      expect(
          () => assertCreative(creativeWith(experience(expiresAt: expiry)),
              {'interactiveExperience': claim}, [],
              responseReceivedAt: DateTime.utc(2029, 12, 31)),
          returnsNormally);
    });

    test('the SDK-internal launch accessor is what is asserted', () {
      final e = experience();
      expect(leadGenerationLaunch(e).launchUrl.scheme, 'https');
    });
  });

  group('resolveLeadGenBaseUrl', () {
    final lan = InternetAddress('192.168.1.20');
    final lo = InternetAddress('127.0.0.1');

    test('the env value wins', () {
      expect(
          resolveLeadGenBaseUrl(
              envValue: 'https://engine.example.com/',
              baseUrl: 'http://127.0.0.1:8080',
              addresses: [lan]),
          'https://engine.example.com');
    });

    test(
        'a loopback base keeps scheme and port and takes the first non-loopback IPv4',
        () {
      expect(
          resolveLeadGenBaseUrl(
              envValue: null,
              baseUrl: 'http://127.0.0.1:8080',
              addresses: [lo, lan, InternetAddress('10.0.0.9')]),
          'http://192.168.1.20:8080');
      expect(
          resolveLeadGenBaseUrl(
              envValue: '', baseUrl: 'http://localhost:8090', addresses: [lan]),
          'http://192.168.1.20:8090');
    });

    test('a loopback env value is refused, never used', () {
      for (final bad in [
        'http://127.0.0.1:8080',
        'http://localhost:8080',
        'nonsense'
      ]) {
        expect(
            () => resolveLeadGenBaseUrl(
                envValue: bad,
                baseUrl: 'http://127.0.0.1:8080',
                addresses: [lan]),
            throwsA(isA<StateError>().having(
                (e) => e.message, 'message', contains(leadGenBaseUrlEnv))),
            reason: bad);
      }
    });

    test('a non-loopback base is kept unchanged', () {
      expect(
          resolveLeadGenBaseUrl(
              envValue: null,
              baseUrl: 'https://engine.internal:8443',
              addresses: [lan]),
          'https://engine.internal:8443');
    });

    test('no non-loopback address fails naming the env var, never loopback',
        () {
      expect(
          () => resolveLeadGenBaseUrl(
              envValue: null,
              baseUrl: 'http://127.0.0.1:8080',
              addresses: [lo]),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('ADMOAI_LEAD_GEN_E2E_BASE_URL'))));
    });
  });
}

Map<String, dynamic> _json(String body) =>
    jsonDecode(body) as Map<String, dynamic>;
