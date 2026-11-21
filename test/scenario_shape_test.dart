import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e/manifest_runner.dart';

// Offline proof of the live runner's scenario-shape gate and of how `request.device` reaches the
// wire. No engine: the live proof is test/e2e/journey_e2e_test.dart.

Map<String, dynamic> _entry({
  Map<String, dynamic> request = const {},
  Map<String, dynamic> expectation = const {},
}) => {
  'id': 'X1',
  'title': 't',
  'request': {
    'placements': [
      {'key': 'home'},
    ],
    ...request,
  },
  'expect': {'outcome': 'served', ...expectation},
};

void main() {
  test('every entry of the vendored manifest validates clean', () {
    final manifest =
        jsonDecode(File('test/e2e/scenarios.json').readAsStringSync())
            as Map<String, dynamic>;
    final scenarios = (manifest['scenarios'] as List)
        .cast<Map<String, dynamic>>();
    expect(scenarios, isNotEmpty);
    for (final e in scenarios) {
      expect(validateScenarioShape(e), isEmpty, reason: '${e['id']}');
    }
  });

  group('shape problems', () {
    void bad(String name, Map<String, dynamic> entry, String mention) =>
        test(name, () {
          final problems = validateScenarioShape(entry);
          expect(problems, isNotEmpty);
          expect(problems.join(), contains(mention));
        });

    bad('unknown request key', _entry(request: {'bogus': 1}), 'bogus');
    bad('unknown expect key', _entry(expectation: {'bogus': 1}), 'bogus');
    bad(
      'unknown device key',
      _entry(
        request: {
          'device': {'model': 'x'},
        },
      ),
      'model',
    );
    bad(
      'category watch',
      _entry(
        request: {
          'device': {'category': 'watch'},
        },
      ),
      'category',
    );
    bad(
      'category null',
      _entry(
        request: {
          'device': {'category': null},
        },
      ),
      'category',
    );
    bad(
      'carrier 42',
      _entry(
        request: {
          'device': {'carrier': 42},
        },
      ),
      'carrier',
    );
    bad(
      'custom value 3',
      _entry(
        request: {
          'custom': [
            {'key': 'k', 'value': 3},
          ],
        },
      ),
      'custom',
    );
    bad(
      'custom value object',
      _entry(
        request: {
          'custom': [
            {
              'key': 'k',
              'value': {'a': 1},
            },
          ],
        },
      ),
      'custom',
    );
    bad(
      'custom value list of ints',
      _entry(
        request: {
          'custom': [
            {
              'key': 'k',
              'value': [1],
            },
          ],
        },
      ),
      'custom',
    );
  });

  test(
    'a device with carrier and category, and a list custom value, are valid',
    () {
      expect(
        validateScenarioShape(
          _entry(
            request: {
              'device': {'carrier': ' Example Mobile ', 'category': 'tablet'},
              'custom': [
                {
                  'key': 'k',
                  'value': ['a', 'b'],
                },
              ],
            },
          ),
        ),
        isEmpty,
      );
    },
  );

  group('request.device reaches the wire as the manual device config', () {
    String body(Map<String, dynamic> device) {
      final sdk = AdMoai.forTesting(
        config: SDKConfig(baseUrl: 'https://mock.api.admoai.com'),
      );
      applyScenarioDevice(sdk, device);
      final request = sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .build();
      return sdk.getHttpRequest(request).body ?? '';
    }

    test('carrier is normalised and category sent', () {
      final b = body({'carrier': ' Example Mobile ', 'category': 'tablet'});
      expect(b, contains('"carrier":"Example Mobile"'));
      expect(b, contains('"category":"tablet"'));
    });

    test('a wifi carrier yields no carrier', () {
      expect(body({'carrier': 'wifi'}), isNot(contains('"carrier"')));
    });
  });
}
