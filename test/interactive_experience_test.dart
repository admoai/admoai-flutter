import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

/// The scenarios of `lib/src/models/interactive_experience.feature`, one test
/// per scenario, named after it. `every scenario has a test` holds the binding.
/// Fixtures are the contract pack's, under `test/fixtures/interactive_experience`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;

  const dir = 'test/fixtures/interactive_experience';
  final scenarios = <String>{};

  void scenario(String title, Future<void> Function() body) {
    scenarios.add(title);
    test(title, body);
  }

  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('$dir/$name').readAsStringSync()) as Map<String, dynamic>;

  Map<String, dynamic> descriptor() => Map<String, dynamic>.from(
      fixture('creative-descriptor.json')['interactiveExperience'] as Map);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'), (_) async => 'UTC');
  });

  ({AdMoai sdk, List<http.Request> sent, List<LogRecord> logs}) build({
    InteractiveExperienceIntegration? integration,
    String? apiVersion = '2025-11-01',
    String responseBody = '{"success":true,"data":[]}',
  }) {
    final sent = <http.Request>[];
    final logs = <LogRecord>[];
    final logger = Logger('ie-${scenarios.length}-${sent.hashCode}')
      ..level = Level.ALL
      ..onRecord.listen(logs.add);
    final sdk = AdMoai.forTesting(
      config: SDKConfig(
        baseUrl: 'https://mock.api.admoai.com',
        apiVersion: apiVersion,
        logger: logger,
        interactiveExperience: integration,
      ),
      httpClient: MockClient((r) async {
        sent.add(r);
        return http.Response(responseBody, 200);
      }),
    );
    return (sdk: sdk, sent: sent, logs: logs);
  }

  DecisionRequest request(AdMoai sdk) =>
      (sdk.createRequestBuilder()..addPlacement(key: 'ride_summary_banner'))
          .build();

  Map<String, dynamic> bodyOf(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  Map<String, dynamic> creativeJson([Map<String, dynamic>? experience]) => {
        'contents': [],
        'advertiser': {},
        'tracking': {},
        if (experience != null) 'interactiveExperience': experience,
      };

  String responseWith(List<List<Map<String, dynamic>>> placements) =>
      jsonEncode({
        'success': true,
        'data': [
          for (var i = 0; i < placements.length; i++)
            {'placement': 'p$i', 'creatives': placements[i]},
        ],
      });

  Future<List<Creative>> decode(String body) async {
    final t = build(responseBody: body);
    final res = await t.sdk.requestAds(request(t.sdk));
    return [
      for (final d in res.body.data!) ...(d.creatives ?? const <Creative>[]),
    ];
  }

  test('every scenario has a test', () {
    final titles = File('lib/src/models/interactive_experience.feature')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('Scenario:'))
        .map((l) => l.substring('Scenario:'.length).trim())
        .toSet();

    expect(titles, isNotEmpty);
    expect(titles, equals(scenarios));
  });

  test('the SDK keys match the contract catalog, in order', () {
    final catalog = fixture('standard-fields.json');
    expect(StandardAttributeKey.values.map((k) => k.wireName).toList(),
        equals((catalog['prefillKeys'] as List).cast<String>()));
  });

  scenario('An SDK update alone does not advertise Lead Generation', () async {
    final t = build();
    await t.sdk.requestAds(request(t.sdk));
    expect(bodyOf(t.sent.single).containsKey('interactiveExperience'), isFalse);
    expect(
        t.sdk
            .getHttpRequest(request(t.sdk))
            .body!
            .contains('interactiveExperience'),
        isFalse);
  });

  scenario('An app that hosts the form advertises the keys it can fill',
      () async {
    final t = build(
      integration: InteractiveExperienceIntegration(
          valueProvider: _Provider({
        StandardAttributeKey.phone,
        StandardAttributeKey.email,
        StandardAttributeKey.fullName,
      })),
    );
    await t.sdk.requestAds(request(t.sdk));
    final expected =
        fixture('request-supported-with-keys.json')['interactiveExperience'];
    expect(bodyOf(t.sent.single)['interactiveExperience'], equals(expected));
    expect((expected as Map)['availableAttributeKeys'],
        equals(['fullName', 'email', 'phone']));
  });

  scenario('An app with no prefill still advertises support', () async {
    final t = build(integration: const InteractiveExperienceIntegration());
    await t.sdk.requestAds(request(t.sdk));
    expect(
        bodyOf(t.sent.single)['interactiveExperience'],
        equals(fixture(
            'request-supported-empty-keys.json')['interactiveExperience']));
  });

  scenario('Building and sending a request never reads a value', () async {
    final provider = _Provider({StandardAttributeKey.email});
    final t = build(
        integration: InteractiveExperienceIntegration(valueProvider: provider));
    await t.sdk.requestAds(request(t.sdk));
    t.sdk.getHttpRequest(request(t.sdk));
    expect(provider.valueCalls, 0);
  });

  scenario('A provider that fails to list keys does not block the request',
      () async {
    final t = build(
        integration:
            InteractiveExperienceIntegration(valueProvider: _ThrowingKeys()));
    await t.sdk.requestAds(request(t.sdk));
    expect(bodyOf(t.sent.single)['interactiveExperience'],
        equals({'supported': true, 'availableAttributeKeys': <String>[]}));
    expect(t.logs.map((r) => r.message).join('\n'),
        isNot(contains('secret-user-data')));
  });

  scenario('Each creative carries its own experience', () async {
    final creatives = await decode(responseWith([
      [creativeJson(descriptor()), creativeJson()],
      [creativeJson()],
    ]));
    expect(creatives, hasLength(3));
    final d = descriptor();
    final lead = creatives[0].interactiveExperience as LeadGenerationExperience;
    expect(lead.type, 'lead_generation');
    expect(lead.formId, d['formId']);
    expect(lead.preparedVersionId, d['preparedVersionId']);
    expect(lead.formInstanceId, d['formInstanceId']);
    expect(lead.launchUrl, Uri.parse(d['launchUrl'] as String));
    expect(lead.preparationToken, d['preparationToken']);
    expect(lead.expiresAt, DateTime.utc(2026, 11, 12, 15, 15));
    expect(lead.expiresAt.isUtc, isTrue);
    expect(lead.prefillAttributeKeys,
        [StandardAttributeKey.fullName, StandardAttributeKey.email]);
    expect(creatives[1].interactiveExperience, isNull);
    expect(creatives[2].interactiveExperience, isNull);
  });

  scenario('Responses without an experience are unchanged', () async {
    final creatives = await decode(responseWith([
      [creativeJson(), creativeJson()],
    ]));
    expect(creatives, isNotEmpty);
    expect(creatives.every((c) => c.interactiveExperience == null), isTrue);
  });

  scenario('An unknown experience type is exposed as unsupported', () async {
    final creatives = await decode(responseWith([
      [
        creativeJson({'type': 'quiz'}),
        creativeJson(descriptor()),
      ],
    ]));
    final u = creatives[0].interactiveExperience;
    expect(u, isA<UnsupportedInteractiveExperience>());
    expect(u!.type, 'quiz');
    expect(creatives[1].interactiveExperience, isA<LeadGenerationExperience>());
  });

  scenario('A malformed experience is exposed as unsupported', () async {
    Map<String, dynamic> without(String k) => descriptor()..remove(k);
    final cases = <String, dynamic>{
      'non-map': 'lead_generation',
      'missing token': without('preparationToken'),
      'blank formId': descriptor()..['formId'] = '   ',
      'http launchUrl': descriptor()
        ..['launchUrl'] = 'http://api.tenant.example.invalid/x',
      'unparsable expiresAt': descriptor()..['expiresAt'] = 'tomorrow',
      'prefill not a list': descriptor()..['prefillAttributeKeys'] = 'email',
    };
    for (final entry in cases.entries) {
      final creatives = await decode(responseWith([
        [
          creativeJson(descriptor()),
          creativeJson(null)..['interactiveExperience'] = entry.value
        ],
      ]));
      final x = creatives[1].interactiveExperience;
      expect(x, isA<UnsupportedInteractiveExperience>(), reason: entry.key);
      expect(
          creatives[0].interactiveExperience, isA<LeadGenerationExperience>(),
          reason: entry.key);
      if (entry.value is Map) {
        expect(x!.type, 'lead_generation', reason: entry.key);
      } else {
        expect(x!.type, isNull, reason: entry.key);
      }
    }
  });

  scenario('Keys the SDK does not know are ignored', () async {
    final unknown = fixture('request-unknown-key.json')['interactiveExperience']
        as Map<String, dynamic>;
    final creatives = await decode(responseWith([
      [
        creativeJson(descriptor()
          ..['prefillAttributeKeys'] = unknown['availableAttributeKeys'])
      ],
    ]));
    expect(
        (creatives.single.interactiveExperience as LeadGenerationExperience)
            .prefillAttributeKeys,
        [StandardAttributeKey.email]);
  });

  scenario('The preparation token never appears in debug output', () async {
    final creatives = await decode(responseWith([
      [creativeJson(descriptor())],
    ]));
    final token = descriptor()['preparationToken'] as String;
    final experience = creatives.single.interactiveExperience!;
    expect(experience.toString(), isNot(contains(token)));
    expect(creatives.single.toString(), isNot(contains(token)));
    expect(experience.toString(), contains('<redacted>'));
  });

  scenario('Opting in without an API version warns the integrator', () async {
    final t = build(
        apiVersion: null,
        integration: const InteractiveExperienceIntegration());
    await t.sdk.requestAds(request(t.sdk));
    final warnings = t.logs
        .where((r) =>
            r.level == Level.WARNING &&
            r.message.contains('Interactive experience integration set but'))
        .length;
    expect(warnings, 1);
  });
}

class _Provider implements StandardValueProvider {
  _Provider(this.availableKeys);

  @override
  final Set<StandardAttributeKey> availableKeys;
  int valueCalls = 0;

  @override
  Future<String?> valueFor(StandardAttributeKey key) async {
    valueCalls++;
    return 'value';
  }
}

class _ThrowingKeys implements StandardValueProvider {
  @override
  Set<StandardAttributeKey> get availableKeys =>
      throw StateError('secret-user-data');

  @override
  Future<String?> valueFor(StandardAttributeKey key) async => null;
}
