import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';

import 'journey_e2e_harness.dart';

/// Shared cross-SDK manifest interpreter.
///
/// Executes `scenarios.json`, the cross-SDK scenario manifest. The manifest is the single
/// definition of each declarative scenario; this file is only the Dart interpreter for it.
///
/// Why a manifest: the 37 hand-written journey scenarios exist three times, once per language,
/// and they had ALREADY drifted — Android's K1 asserted less than iOS's and Flutter's, which is
/// why a pinned-ULID bug failed on only two of three suites. Every hand-written scenario is three
/// more chances to diverge. Here a scenario is added once, as data, and all three SDKs execute the
/// same claims.
///
/// Scope: declarative scenarios only. Anything procedural (log capture, concurrency, retry, TTL
/// sleeps) stays hand-written, because that genuinely differs per platform.

Map<String, dynamic> loadManifest() {
  // Resolved relative to the test file so it works under `flutter test` from any cwd.
  final file = File('test/e2e/scenarios.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void manifestGroup(E2eReport report) {
  final manifest = loadManifest();
  final scenarios = (manifest['scenarios'] as List).cast<Map<String, dynamic>>();

  for (final entry in scenarios) {
    scenario(
      report,
      entry['id'] as String,
      entry['title'] as String,
      (notes) => _run(entry, notes),
    );
  }
}

Future<void> _run(Map<String, dynamic> entry, List<String> notes) async {
  final request = entry['request'] as Map<String, dynamic>;
  final expect = entry['expect'] as Map<String, dynamic>;

  // 'none' means: no apiVersion at all, so no version header is sent.
  final rawVersion = request['apiVersion'] as String?;
  final driver = await (rawVersion == null
      ? newDriver()
      : newDriver(apiVersion: rawVersion == 'none' ? null : rawVersion));

  try {
    final builder = driver.sdk.createRequestBuilder();
    for (final p in (request['placements'] as List).cast<Map<String, dynamic>>()) {
      builder.addPlacement(
        key: p['key'] as String,
        count: p['count'] as int?,
        format: _format(p['format'] as String?),
        advertiserId: p['advertiserId'] as String?,
        templateId: p['templateId'] as String?,
      );
    }
    for (final c in ((request['custom'] as List?) ?? []).cast<Map<String, dynamic>>()) {
      builder.addCustomTargeting(key: c['key'] as String, value: c['value']);
    }
    if (request['session'] != null) {
      builder.setSessionId(freshSession((entry['id'] as String).toLowerCase()));
    }
    if (request['journeyOpt'] != null) {
      builder.setJourneyOpt(
          request['journeyOpt'] == 'in' ? JourneyOpt.optIn : JourneyOpt.optOut);
    }

    final outcome = expect['outcome'] as String;

    // --- error outcomes ---------------------------------------------------------------
    if (outcome == 'error') {
      final expectedError = expect['error'] as Map<String, dynamic>;
      final kind = expectedError['kind'] as String;
      try {
        final built = builder.build();
        await driver.sdk.requestAds(built);
        check(false, 'the request is rejected (it succeeded instead)');
      } on ArgumentError catch (e) {
        check(kind == 'local', 'a local SDK error is expected for this scenario (got $e)');
        notes.add('rejected locally as ArgumentError, no network call');
        return;
      } on ValidationError catch (e) {
        check(kind != 'local', 'the SDK rejects this before any network call');
        final code = expectedError['code'] as int?;
        if (code != null) {
          check(e.errors.any((err) => err.code == code),
              'the engine error code is $code (got ${e.errors.map((x) => x.code).toList()})');
        }
        notes.add('rejected with ${e.errors.map((x) => '[${x.code}] ${x.message}').join()}');
        return;
      }
      return;
    }

    // --- served / no-ad ---------------------------------------------------------------
    final response = await driver.sdk.requestAds(builder.build());
    final decisions = response.body.data ?? <Decision>[];

    final expectedDecisions = expect['decisions'] as int?;
    if (expectedDecisions != null) {
      check(decisions.length == expectedDecisions,
          'the response carries $expectedDecisions decision(s) (got ${decisions.length})');
    }
    if (expect['decisionsMatchRequest'] == true) {
      final requested = (request['placements'] as List)
          .cast<Map<String, dynamic>>()
          .map((p) => p['key'] as String)
          .toSet();
      final returned = decisions.map((d) => d.placement).toSet();
      check(requested.difference(returned).isEmpty && returned.difference(requested).isEmpty,
          'every requested placement is keyed back: $requested vs $returned');
    }

    check(decisions.isNotEmpty, 'at least one decision is returned');
    final decision = decisions.first;
    final creatives = decision.creatives ?? <Creative>[];

    if (outcome == 'noAd') {
      check(decision.isNoAd, 'the decision is a clean no-ad (got ${creatives.length} creatives)');
      check(!decision.hasCreative, 'hasCreative is false');
      notes.add('no-ad on ${decision.placement}, nothing exposed to fire');
      return;
    }

    check(decision.hasCreative, 'a creative is served on ${decision.placement}');

    final atMost = expect['creativesAtMost'] as int?;
    if (atMost != null) {
      check(creatives.length <= atMost,
          'at most $atMost creatives are returned (got ${creatives.length})');
      notes.add('returned ${creatives.length} creative(s)');
    }
    if (expect['creativesDistinct'] == true && creatives.length > 1) {
      final ids = creatives.map((c) => c.metadata?.creativeId).whereType<String>().toList();
      check(ids.toSet().length == ids.length, 'the returned creatives are distinct (got $ids)');
    }

    final creativeExpect = expect['creative'] as Map<String, dynamic>?;
    if (creativeExpect != null) {
      _assertCreative(creatives.first, creativeExpect, notes);
    }
  } finally {
    driver.dispose();
  }
}

Format? _format(String? raw) {
  switch (raw) {
    case 'native':
      return Format.native;
    case 'video':
      return Format.video;
    default:
      return null;
  }
}

void _assertCreative(Creative creative, Map<String, dynamic> e, List<String> notes) {
  if (e['requireMetadata'] == true) {
    final m = creative.metadata;
    check(m != null, 'the creative carries a metadata block');
    check(m!.adId.isNotEmpty, 'metadata.adId is non-empty');
    check(m.creativeId.isNotEmpty, 'metadata.creativeId is non-empty');
    check(m.placementId.isNotEmpty, 'metadata.placementId is non-empty');
    check(m.templateId.isNotEmpty, 'metadata.templateId is non-empty');
    notes.add('metadata: ad=${m.adId} creative=${m.creativeId}');
  }
  final priorityIn = (e['priorityIn'] as List?)?.cast<String>();
  if (priorityIn != null && creative.metadata != null) {
    check(priorityIn.contains(creative.metadata!.priority.value),
        'priority is one of $priorityIn (got ${creative.metadata!.priority.value})');
  }
  if (e['requireAdvertiser'] == true) {
    final a = creative.advertiser;
    check((a.name ?? '').isNotEmpty, 'advertiser.name is non-empty');
    check((a.legalName ?? '').isNotEmpty, 'advertiser.legalName is non-empty');
    check((a.logoUrl ?? '').isNotEmpty, 'advertiser.logoUrl is non-empty');
  }
  if (e['requireTemplate'] == true) {
    check((creative.template?.key ?? '').isNotEmpty, 'template.key is non-empty');
  }
  if (e['requireContents'] == true) {
    check(creative.contents.hasContents(), 'the creative carries content fields');
    notes.add('${creative.contents.length} content field(s)');
  }
  if (e['journey'] != null) {
    check(creative.isJourneyAd() == e['journey'],
        'isJourneyAd is ${e['journey']} (got ${creative.isJourneyAd()})');
  }
  if (e['formatEquals'] != null) {
    check(creative.metadata?.format == e['formatEquals'],
        'metadata.format is "${e['formatEquals']}" (got ${creative.metadata?.format})');
  }
  if (e['deliveryEquals'] != null) {
    check(creative.delivery == e['deliveryEquals'],
        'delivery is "${e['deliveryEquals']}" (got ${creative.delivery})');
  }
  switch (e['impressions']) {
    case 'required':
      check((creative.tracking.impressions ?? []).isNotEmpty, 'an impression URL is exposed');
      break;
    case 'forbidden':
      check((creative.tracking.impressions ?? []).isEmpty,
          'NO engine-side impression URL is exposed (VAST owns it; both would double-count)');
      break;
  }
  final clicksAtLeast = e['clicksAtLeast'] as int?;
  if (clicksAtLeast != null) {
    final clicks = creative.tracking.clicks ?? [];
    check(clicks.length >= clicksAtLeast,
        'at least $clicksAtLeast click URL(s) exposed (got ${clicks.length})');
  }
  final videoCount = e['videoEventCount'] as int?;
  if (videoCount != null) {
    final events = creative.tracking.videoEvents ?? [];
    check(events.length == videoCount,
        'exactly $videoCount video event URL(s) exposed (got ${events.length}: ${events.map((v) => v.key).toList()})');
  }
  final videoKeys = (e['videoEventKeys'] as List?)?.cast<String>();
  if (videoKeys != null) {
    final actual = (creative.tracking.videoEvents ?? []).map((v) => v.key).toSet();
    check(videoKeys.every(actual.contains),
        'video events include $videoKeys (got ${actual.toList()..sort()})');
  }
  if (e['requireVastTagUrl'] == true) {
    check((creative.getVastTagUrl() ?? '').isNotEmpty, 'a VAST tag URL is exposed');
    check(creative.isVastTagDelivery(), 'isVastTagDelivery() agrees with the delivery mode');
  }
  if (e['requireVastXmlDecodes'] == true) {
    final b64 = creative.getVastXmlBase64();
    check(b64 != null, 'vast.xmlBase64 is present');
    final xml = utf8.decode(base64Decode(b64!));
    check(xml.contains('<VAST'), 'the decoded payload is a VAST document');
    check(creative.isVastXmlDelivery(), 'isVastXmlDelivery() agrees with the delivery mode');
  }
  if (e['metadataIsSkippable'] != null) {
    check(creative.metadata?.isSkippable == e['metadataIsSkippable'],
        'metadata.isSkippable is ${e['metadataIsSkippable']} (got ${creative.metadata?.isSkippable})');
  }
  final skipSeconds = e['skipOffsetSecondsEquals'] as int?;
  if (skipSeconds != null) {
    check(creative.metadata?.skipOffsetSeconds == skipSeconds,
        'metadata.skipOffsetSeconds is $skipSeconds (got ${creative.metadata?.skipOffsetSeconds})');
  }
  if (e['helperIsSkippable'] != null) {
    // Proves the helper reads ENGINE metadata rather than falling through to content fields —
    // the Wave 2 fix, which no live scenario exercised until now.
    check(creative.isSkippable() == e['helperIsSkippable'],
        'isSkippable() is ${e['helperIsSkippable']} (got ${creative.isSkippable()})');
  }
  if (e['helperSkipOffsetEquals'] != null) {
    check(creative.getSkipOffset() == e['helperSkipOffsetEquals'],
        'getSkipOffset() is "${e['helperSkipOffsetEquals']}" (got ${creative.getSkipOffset()})');
  }
  if (e['endCardModeEquals'] != null) {
    check(creative.metadata?.endCardMode == e['endCardModeEquals'],
        'metadata.endCardMode is "${e['endCardModeEquals']}" (got ${creative.metadata?.endCardMode})');
  }
}

// §U wire shape (hand-written: needs the built request, not a served response)
//
// Procedural rather than manifest-driven: these assert what the SDK PUTS ON THE WIRE, which the
// declarative interpreter never inspects. `getHttpRequest` builds body and headers without
// sending, so the whole group is offline and deterministic.

void wireShapeGroup(E2eReport report) {
  scenario(report, 'U1',
      'the canonical request body uses the engine\'s canonical key names', (notes) async {
    final driver = await newDriver();
    try {
      final request = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setUserId('u-1')
          .addGeoTargeting(5128581)
          .addLocationTargeting(latitude: 40.7, longitude: -74.0)
          .addDestinationTargeting(latitude: 41.0, longitude: -73.0, minConfidence: 0.8)
          .build();
      final body = driver.sdk.getHttpRequest(request).body ?? '';

      // `minConfidence` is canonical; `min_confidence` is a back-compat alias the engine keeps
      // only for already-fielded SDKs. A new version must not emit the alias.
      check(body.contains('"minConfidence"'), 'destination uses the canonical camelCase key');
      check(!body.contains('min_confidence'), 'the legacy snake_case alias is NOT emitted');
      check(body.contains('"placements"'), 'placements are present');
      notes.add('body keys verified against the engine\'s canonical contract');
    } finally {
      driver.dispose();
    }
  });

  scenario(report, 'U2', 'decision headers carry version, language and the SDK User-Agent',
      (notes) async {
    final driver = await newDriver();
    try {
      final request = driver.sdk.createRequestBuilder().addPlacement(key: 'home').build();
      final headers = driver.sdk.getHttpRequest(request).headers ?? {};

      check(headers['X-Decision-Version'] == e2eApiVersion,
          'X-Decision-Version is $e2eApiVersion (got ${headers['X-Decision-Version']})');
      check((headers['User-Agent'] ?? '').startsWith('AdMoaiSDK/'),
          'a User-Agent identifying the SDK is sent (got ${headers['User-Agent']})');
      check(headers['Content-Type'] == 'application/json', 'Content-Type is application/json');
      notes.add('headers: ${(headers.keys.toList()..sort()).join(', ')}');
    } finally {
      driver.dispose();
    }
  });

  scenario(report, 'U3', 'omitted optional fields are absent from the body, not sent as null',
      (notes) async {
    final driver = await newDriver();
    try {
      final request = driver.sdk.createRequestBuilder().addPlacement(key: 'home').build();
      final body = driver.sdk.getHttpRequest(request).body ?? '';

      // A tolerant engine accepts nulls, but emitting them makes every payload larger and muddies
      // "the publisher did not set this" versus "the publisher cleared this".
      check(!body.contains('"format"'), 'an unset placement format is omitted entirely');
      check(!body.contains('"count"'), 'an unset count is omitted entirely');
      check(!body.contains('null'), 'no explicit nulls are emitted anywhere in the body');
      notes.add('no nulls, no unset optional keys');
    } finally {
      driver.dispose();
    }
  });

  scenario(report, 'U4', 'disabling app and device collection removes those blocks from the wire',
      (notes) async {
    final driver = await newDriver();
    try {
      final request = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .disableAppCollection()
          .disableDeviceCollection()
          .build();
      final body = driver.sdk.getHttpRequest(request).body ?? '';

      check(!body.contains('"app"'), 'the app block is absent');
      check(!body.contains('"device"'), 'the device block is absent');
      notes.add('app and device omitted on request');
    } finally {
      driver.dispose();
    }
  });

  scenario(report, 'U5', 'Journey context reaches the wire as top-level camelCase', (notes) async {
    final driver = await newDriver();
    try {
      final session = freshSession('u5');
      final request = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: 'home')
          .setSessionId(session)
          .setJourneyOpt(JourneyOpt.optIn)
          .build();
      final body = driver.sdk.getHttpRequest(request).body ?? '';

      check(body.contains('"sessionId":"$session"'), 'sessionId is top-level camelCase');
      check(body.contains('"journeyOpt":"in"'), 'journeyOpt serializes to the wire literal "in"');
      notes.add('journey context verified on the wire');
    } finally {
      driver.dispose();
    }
  });
}
