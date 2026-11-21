import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'e2e/manifest_runner.dart';

/// Offline proof that the live runner sends `request.interactiveExperience` through the SDK's
/// opt-in. The three requests are copied verbatim from scenarios IE1, IE2 and IE3 of the published
/// @admoai/sdk-scenarios 4.0.0 (schemaVersion 7). No network: the HTTP client is a mock.
void main() {
  const ie1 = {
    'apiVersion': '2025-11-01',
    'placements': [
      {'key': 'home'},
    ],
    'interactiveExperience': {
      'supported': true,
      'availableAttributeKeys': ['fullName', 'email', 'phone'],
    },
  };
  const ie2 = {
    'apiVersion': '2025-01-01',
    'placements': [
      {'key': 'home'},
    ],
    'interactiveExperience': {
      'supported': true,
      'availableAttributeKeys': ['fullName', 'email', 'phone'],
    },
  };
  const ie3 = {
    'apiVersion': '2025-11-01',
    'placements': [
      {'key': 'home'},
    ],
    'interactiveExperience': {
      'supported': true,
      'availableAttributeKeys': <String>[],
    },
  };

  tearDown(() => AdMoai.secureSurfaceAvailableForTesting = null);

  AdMoai newSdk(String apiVersion) => AdMoai.forTesting(
    config: SDKConfig(
      baseUrl: 'https://mock.api.admoai.com',
      apiVersion: apiVersion,
    ),
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
    test(
      '$name: the request body carries the scenario interactiveExperience',
      () {
        final entry = {'id': name, 'request': request, 'expect': {}};
        expect(validateScenarioShape(entry), isEmpty);
        final body = bodyFor(request);
        expect(
          _json(body)['interactiveExperience'],
          equals(request['interactiveExperience']),
        );
      },
    );
  }

  test('an unknown attribute key fails with an interpreter error', () {
    final request = {
      ...ie1,
      'interactiveExperience': {
        'supported': true,
        'availableAttributeKeys': ['fullName', 'shoeSize'],
      },
    };
    expect(
      validateScenarioShape({'id': 'X', 'request': request, 'expect': {}}),
      isNotEmpty,
    );
    expect(() => bodyFor(request), throwsA(isA<StateError>()));
  });

  test('another shape fails too, never silently dropped', () {
    for (final bad in [
      'yes',
      {'supported': false, 'availableAttributeKeys': <String>[]},
      {'supported': true, 'availableAttributeKeys': 'email'},
    ]) {
      expect(
        () => applyScenarioInteractiveExperience(newSdk('2025-11-01'), bad),
        throwsA(isA<StateError>()),
      );
    }
  });

  test('a request without it sends no interactiveExperience', () {
    final body = bodyFor({
      'apiVersion': '2025-11-01',
      'placements': [
        {'key': 'home'},
      ],
    });
    expect(_json(body).containsKey('interactiveExperience'), isFalse);
  });

  test('schemaVersion 7 is accepted and 8 refused', () {
    expect(() => requireSupportedSchemaVersion(7), returnsNormally);
    expect(() => requireSupportedSchemaVersion(6), returnsNormally);
    expect(() => requireSupportedSchemaVersion(8), throwsStateError);
  });
}

Map<String, dynamic> _json(String body) =>
    jsonDecode(body) as Map<String, dynamic>;
