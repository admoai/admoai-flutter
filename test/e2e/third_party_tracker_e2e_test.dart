// ignore_for_file: avoid_print
@Tags(['e2e'])
library;

//
// Third-party Event Trackers — live, SDK-driven E2E runner (Flutter).
//
// Drives the **real** SDK against a **locally-running decision-engine** and a
// **real local Turso**, asserting only what a customer's app can observe: the
// decoded model, the `/decision` transport, and the exact URLs the SDK put on
// the wire (via the harness's `RecordingClient`, which records before sending —
// so a `.invalid` tracker host proves byte-identity without needing a live
// agency endpoint). Unit tests prove the SDK against fixtures we wrote; this
// proves the SDK and the engine agree end-to-end: DB rows → engine effective-set
// resolution → wire contract → tolerant decode → fan-out.
//
// NOT part of the hermetic gate. Requires the local stack (`make start` in
// adhub) with the engine gates ON (`is_third_party_trackers_enabled`). Run:
//
//   flutter test test/e2e/third_party_tracker_e2e_test.dart --reporter expanded
//
// The suite SEEDS ITS OWN FIXTURES over the local Turso HTTP API (attaching
// tracker rows to seeded entities), waits for the engine's replica to see them,
// and deletes them in tearDown — re-runnable, and it never touches trackers a
// human configured (rows are namespaced by the `e2e-tpt.invalid` host).
//
// Environment:
//   ADMOAI_JOURNEY_E2E_BASE_URL  default http://127.0.0.1:8080
//   ADMOAI_JOURNEY_E2E_VERSION   default 2025-11-01
//   ADMOAI_E2E_DB_URL            default http://127.0.0.1:8081

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:admoai/admoai.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'journey_e2e_harness.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Seeded classic ad: native, json delivery, template with click events
/// `slide1/slide2/slide3` (and NO `default` click — which is what lets the
/// suite prove the no-canonical-key case end-to-end).
const classicAdPublicId = 'ad_00GQPK31C0KE5E8TQN5422A3AM';
const classicPlacement = 'promotions';
const classicSpecificKey = 'slide1';
const classicOtherKey = 'slide2';

/// Seeded journey deal (mandatory two-stage). Deal-level trackers must ride
/// along on every stage; its node-template click-event union is `default`.
const journeyDealPublicId = 'jad_01M2TJW34GKEC2PF6ZN8FN3BX0';
const journeyStage1Placement = 'sdk_e2e_mandatory_early';
const journeyStage2Placement = 'sdk_e2e_mandatory_later';
const journeyClickKey = 'default';

/// Seeded journey deal with NO trackers — the absent-field case.
const noTrackerPlacement = 'sdk_e2e_optskip_early';

/// Every fixture URL lives on this host: `.invalid` never resolves (the
/// dispatch attempt is recorded before DNS fails and the failure is swallowed),
/// and setup/teardown delete exclusively by this prefix so human-configured
/// trackers are never touched.
const trackerHost = 'e2e-tpt.invalid';
const trackerUrlPrefix = 'https://$trackerHost/';

const classicImpUrl = 'https://$trackerHost/classic/imp?b=2&a=1&ord=12345';
const classicAnyUrl = 'https://$trackerHost/classic/click-any';
const classicSpecUrl = 'https://$trackerHost/classic/click-$classicSpecificKey';
const journeyImpUrl = 'https://$trackerHost/journey/imp';
const journeyAnyUrl = 'https://$trackerHost/journey/click-any';
const journeySpecUrl = 'https://$trackerHost/journey/click-$journeyClickKey';

// ── Local Turso (sqld) access ───────────────────────────────────────────────

final String e2eDbUrl =
    (Platform.environment['ADMOAI_E2E_DB_URL'] ?? 'http://127.0.0.1:8081')
        .replaceAll(RegExp(r'/+$'), '');

/// Executes one statement over sqld's HTTP pipeline API and returns rows as
/// lists of string values (sqld encodes every scalar as a string).
Future<List<List<String?>>> db(String sql) async {
  final response = await http.post(
    Uri.parse('$e2eDbUrl/v2/pipeline'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'requests': [
        {
          'type': 'execute',
          'stmt': {'sql': sql},
        },
        {'type': 'close'},
      ],
    }),
  );
  if (response.statusCode != 200) {
    throw StateError('sqld answered HTTP ${response.statusCode}');
  }
  final first =
      (jsonDecode(response.body)['results'] as List).first as Map<String, dynamic>;
  if (first['type'] != 'ok') {
    throw StateError('sqld error: ${jsonEncode(first)}');
  }
  final result = first['response']['result'] as Map<String, dynamic>;
  return (result['rows'] as List)
      .map((row) => (row as List)
          .map((cell) => (cell as Map<String, dynamic>)['value'] as String?)
          .toList())
      .toList();
}

/// A fresh `tpt_` public id in the Crockford alphabet the schema CHECK demands.
String freshTrackerId() {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final rng = Random();
  return 'tpt_${List.generate(26, (_) => alphabet[rng.nextInt(alphabet.length)]).join()}';
}

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

/// Quotes a value for inline SQL (fixture values are all suite-owned constants).
String sq(String? value) =>
    value == null ? 'NULL' : "'${value.replaceAll("'", "''")}'";

// ── Suite state resolved during preflight ───────────────────────────────────

late final String seedUserId;
late final int classicAdId;
late final int classicTemplateId;
late final int classicSpecificEventId;
late final int journeyDealId;

Future<void> deleteFixtures() async {
  // The E03 triggers forbid hard DELETE (soft-delete convention). Deleted rows
  // never serve and are excluded from the duplicate/limit guards, so re-runs
  // can re-insert the same URLs cleanly.
  await db("UPDATE ad_third_party_trackers SET status = 'deleted', "
      'updated_by = ${sq(seedUserId)} '
      "WHERE tracking_url LIKE '$trackerUrlPrefix%' AND status != 'deleted'");
  await db("UPDATE journey_deal_third_party_trackers SET status = 'deleted', "
      'updated_by = ${sq(seedUserId)} '
      "WHERE tracking_url LIKE '$trackerUrlPrefix%' AND status != 'deleted'");
}

Future<void> insertAdTracker({
  required int adId,
  required String eventType,
  String? matchType,
  int? templateEventId,
  String? eventKey,
  required String url,
}) async {
  await db('INSERT INTO ad_third_party_trackers '
      '(public_id, ad_id, event_type, click_match_type, template_event_id, '
      'click_event_key, tracking_url, tracking_url_hash, created_by) VALUES '
      '(${sq(freshTrackerId())}, $adId, ${sq(eventType)}, ${sq(matchType)}, '
      '${templateEventId ?? 'NULL'}, ${sq(eventKey)}, ${sq(url)}, '
      '${sq(sha256Hex(url))}, ${sq(seedUserId)})');
}

Future<void> insertDealTracker({
  required int dealId,
  required String eventType,
  String? matchType,
  String? eventKey,
  required String url,
}) async {
  await db('INSERT INTO journey_deal_third_party_trackers '
      '(public_id, journey_deal_id, event_type, click_match_type, '
      'click_event_key, tracking_url, tracking_url_hash, created_by) VALUES '
      '(${sq(freshTrackerId())}, $dealId, ${sq(eventType)}, ${sq(matchType)}, '
      '${sq(eventKey)}, ${sq(url)}, ${sq(sha256Hex(url))}, ${sq(seedUserId)})');
}

// ── Decision helpers ────────────────────────────────────────────────────────

/// Decides on [placement] until [adPublicId] wins the rotation (competing seed
/// ads share the placement), or fails after [maxAttempts].
Future<Creative> decideUntilAd(
  Driver driver,
  String placement,
  String adPublicId, {
  int maxAttempts = 80,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final served = await decide(
      driver,
      placements: [placement],
      configure: (b) => b.setUserId(freshUser('tpt')),
    );
    final creative = served.creativeFor(placement);
    if (creative?.metadata?.adId == adPublicId) return creative!;
  }
  throw StateError(
      'the fixture ad never won the rotation on "$placement" in $maxAttempts attempts');
}

/// Waits until [predicate] holds over the recorded wire URLs, then settles a
/// little longer so "and nothing else fired" assertions are meaningful.
Future<void> awaitWire(Driver driver, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) break;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  check(predicate(), 'the expected tracker dispatches were recorded on the wire');
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

int countSent(Driver driver, String url) =>
    driver.client.sent.where((u) => u == url).length;

// ── Runner ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final report = E2eReport();

  setUpAll(() async {
    // The harness's per-driver loggers set their own level (log capture for the
    // privacy assertions), which `package:logging` only allows hierarchically.
    hierarchicalLoggingEnabled = true;
    installPlatformChannelStubs();
    assertRealNetworkingEnabled();
    try {
      // Resolve fixtures from the live DB — internal ids differ across reseeds.
      final user = await db('SELECT id FROM users LIMIT 1');
      if (user.isEmpty) throw StateError('no users seeded');
      seedUserId = user.first.first!;

      final ad = await db('SELECT id, template_id FROM ads '
          "WHERE public_id = ${sq(classicAdPublicId)} AND status = 'published'");
      if (ad.isEmpty) {
        throw StateError('classic fixture ad $classicAdPublicId is not seeded/published');
      }
      classicAdId = int.parse(ad.first[0]!);
      classicTemplateId = int.parse(ad.first[1]!);

      final event = await db('SELECT id FROM template_events '
          'WHERE template_id = $classicTemplateId AND key = ${sq(classicSpecificKey)} '
          "AND event = 'click' AND status = 'active'");
      if (event.isEmpty) {
        throw StateError('click event "$classicSpecificKey" missing on template $classicTemplateId');
      }
      classicSpecificEventId = int.parse(event.first.first!);

      final deal = await db('SELECT id FROM journey_deals '
          "WHERE public_id = ${sq(journeyDealPublicId)} AND status = 'active'");
      if (deal.isEmpty) {
        throw StateError('journey fixture deal $journeyDealPublicId is not seeded/active');
      }
      journeyDealId = int.parse(deal.first.first!);

      // Idempotent re-seed: drop leftovers from a previous run, insert fresh.
      await deleteFixtures();
      await insertAdTracker(
          adId: classicAdId, eventType: 'impression', url: classicImpUrl);
      await insertAdTracker(
          adId: classicAdId, eventType: 'click', matchType: 'any', url: classicAnyUrl);
      await insertAdTracker(
          adId: classicAdId,
          eventType: 'click',
          matchType: 'specific',
          templateEventId: classicSpecificEventId,
          eventKey: classicSpecificKey,
          url: classicSpecUrl);
      await insertDealTracker(
          dealId: journeyDealId, eventType: 'impression', url: journeyImpUrl);
      await insertDealTracker(
          dealId: journeyDealId, eventType: 'click', matchType: 'any', url: journeyAnyUrl);
      await insertDealTracker(
          dealId: journeyDealId,
          eventType: 'click',
          matchType: 'specific',
          eventKey: journeyClickKey,
          url: journeySpecUrl);

      // Gate + replica-sync probe: the journey deal serves deterministically on
      // its own placement, so trackers must appear once the replica catches up.
      // Their absence after the window means the engine gate is OFF (or the
      // replica is stuck) — an environment fact, diagnosed once.
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      var seen = false;
      while (DateTime.now().isBefore(deadline) && !seen) {
        await withDriver((d) async {
          final served = await decide(
            d,
            placements: [journeyStage1Placement],
            sessionId: freshSession('tpt_preflight'),
            configure: (b) => b.setUserId(freshUser('tpt_preflight')),
          );
          final tracking =
              served.creativeFor(journeyStage1Placement)?.tracking;
          seen = tracking?.thirdPartyTrackers?.isNotEmpty ?? false;
        });
        if (!seen) await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!seen) {
        throw PreflightAbort(
          'the engine never served the seeded third-party trackers',
          recipe: 'is_third_party_trackers_enabled must be ON for the local '
              'engine: doppler secrets get STATSIG_OVERRIDE_GATES -p decision-engine -c local '
              '— then restart the stack; also confirm the Turso replica is syncing',
        );
      }
    } on PreflightAbort catch (abort) {
      report.preflightDiagnosis = abort.diagnosis;
      report.preflightRecipe = abort.recipe;
    } catch (error) {
      report.preflightDiagnosis = error.toString();
    }
  });

  tearDownAll(() async {
    try {
      await deleteFixtures();
    } catch (_) {
      print('WARNING: fixture cleanup failed — rerun deletes by URL prefix.');
    }
    report.printSummary();
  });

  // T1 — the wire contract, end to end: DB rows → engine effective set → SDK model
  scenario(report, 'T1', 'classic ad serves its three trackers byte-identical', (notes) async {
    await withDriver((d) async {
      final creative =
          await decideUntilAd(d, classicPlacement, classicAdPublicId);
      final trackers = creative.tracking.thirdPartyTrackers;
      check(trackers != null && trackers.length == 3,
          'exactly the 3 seeded trackers are served (got ${trackers?.length})');
      final byUrl = {for (final t in trackers!) t.url: t};
      final imp = byUrl[classicImpUrl];
      check(imp != null, 'the impression tracker URL round-tripped byte-identical');
      check(imp!.eventType == 'impression' && imp.matchType == null && imp.eventKey == null,
          'impression entry carries no click fields');
      final any = byUrl[classicAnyUrl];
      check(any != null && any.eventType == 'click' && any.matchType == 'any' && any.eventKey == null,
          'any-click entry shape');
      final spec = byUrl[classicSpecUrl];
      check(spec != null && spec.matchType == 'specific' && spec.eventKey == classicSpecificKey,
          'specific-click entry carries its eventKey');
      check(trackers.every((t) => t.trackerId.startsWith('tpt_')),
          'entries carry tpt_ public ids');
      check(creative.tracking.getImpressionUrl() != null,
          'canonical impression tracking is intact');
      notes.add('served ${trackers.length} trackers on ${creative.metadata?.adId}');
    });
  });

  // T2 — additive by version: the 2025-01-01 handler never sees the field
  scenario(report, 'T2', 'the field is absent under X-Decision-Version 2025-01-01', (notes) async {
    await withDriver((d) async {
      final creative =
          await decideUntilAd(d, classicPlacement, classicAdPublicId);
      check(creative.tracking.thirdPartyTrackers == null,
          'thirdPartyTrackers is absent on the old version');
    }, apiVersion: '2025-01-01');
  });

  // T3 — impression fan-out on the wire, exactly once per invocation
  scenario(report, 'T3', 'fireImpression dispatches the impression tracker once per invocation', (notes) async {
    await withDriver((d) async {
      final creative =
          await decideUntilAd(d, classicPlacement, classicAdPublicId);
      final wireBefore = d.client.sent.length;
      d.sdk.fireImpression(creative.tracking);
      await awaitWire(d, () => countSent(d, classicImpUrl) == 1);
      check(countSent(d, classicAnyUrl) == 0 && countSent(d, classicSpecUrl) == 0,
          'click trackers never fire on an impression');
      check(d.client.sent.length > wireBefore, 'the canonical beacon was attempted too');
      d.sdk.fireImpression(creative.tracking);
      await awaitWire(d, () => countSent(d, classicImpUrl) == 2);
      notes.add('impression tracker attempted exactly once per invocation, twice total');
    });
  });

  // T4 — click matching: any on every valid key, specific only on its key,
  //      and a key with no canonical click fires NOTHING
  scenario(report, 'T4', 'fireClick matches any/specific and refuses unknown keys', (notes) async {
    await withDriver((d) async {
      final creative =
          await decideUntilAd(d, classicPlacement, classicAdPublicId);
      check(creative.tracking.getClickUrl(key: classicOtherKey) != null,
          'fixture sanity: canonical click exists for $classicOtherKey');

      d.sdk.fireClick(creative.tracking, key: classicOtherKey);
      await awaitWire(d, () => countSent(d, classicAnyUrl) == 1);
      check(countSent(d, classicSpecUrl) == 0,
          'specific($classicSpecificKey) does not fire on $classicOtherKey');

      d.sdk.fireClick(creative.tracking, key: classicSpecificKey);
      await awaitWire(d,
          () => countSent(d, classicAnyUrl) == 2 && countSent(d, classicSpecUrl) == 1);

      // This template has NO canonical "default" click, so the default key must
      // fire nothing at all — canonical or third-party.
      check(creative.tracking.getClickUrl() == null,
          'fixture sanity: no canonical default click');
      final before = d.client.sent.length;
      d.sdk.fireClick(creative.tracking);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      check(d.client.sent.length == before,
          'a key without a canonical click fires nothing');
      notes.add('any=2, specific=1, unknown-key=0 dispatches');
    });
  });

  // T5 — journey: the deal-level set rides along on every stage of the session
  scenario(report, 'T5', 'journey deal trackers ride along on every stage', (notes) async {
    await withDriver((d) async {
      final session = freshSession('tpt_stages');
      final user = freshUser('tpt_stages');
      final stage1 = await decide(d,
          placements: [journeyStage1Placement],
          sessionId: session,
          configure: (b) => b.setUserId(user));
      final creative1 = stage1.creativeFor(journeyStage1Placement);
      check(creative1 != null && creative1.journey != null, 'stage 1 served the journey');
      final urls1 =
          (creative1!.tracking.thirdPartyTrackers?.map((t) => t.url).toList() ?? [])
            ..sort();
      final expected = [journeyImpUrl, journeyAnyUrl, journeySpecUrl]..sort();
      check(urls1.join('|') == expected.join('|'),
          'stage 1 carries exactly the 3 deal-level trackers (got $urls1)');

      final stage2 = await decide(d,
          placements: [journeyStage2Placement],
          sessionId: session,
          configure: (b) => b.setUserId(user));
      final creative2 = stage2.creativeFor(journeyStage2Placement);
      check(creative2 != null && creative2.journey != null, 'stage 2 served the journey');
      final urls2 =
          (creative2!.tracking.thirdPartyTrackers?.map((t) => t.url).toList() ?? [])
            ..sort();
      check(urls2.join('|') == urls1.join('|'),
          'stage 2 carries the same deal-level set');
      notes.add('same 3-tracker set on both stages of ${creative1.metadata?.adId}');
    });
  });

  // T6 — journey fan-out through the real helpers
  scenario(report, 'T6', 'journey impression and click fan out from the served creative', (notes) async {
    await withDriver((d) async {
      final served = await decide(d,
          placements: [journeyStage1Placement],
          sessionId: freshSession('tpt_fire'),
          configure: (b) => b.setUserId(freshUser('tpt_fire')));
      final tracking = served.creativeFor(journeyStage1Placement)!.tracking;

      d.sdk.fireImpression(tracking);
      await awaitWire(d, () => countSent(d, journeyImpUrl) == 1);

      check(tracking.getClickUrl(key: journeyClickKey) != null,
          'fixture sanity: canonical click exists for $journeyClickKey');
      d.sdk.fireClick(tracking, key: journeyClickKey);
      await awaitWire(d,
          () => countSent(d, journeyAnyUrl) == 1 && countSent(d, journeySpecUrl) == 1);
      check(countSent(d, journeyImpUrl) == 1, 'impression tracker untouched by the click');
      notes.add('journey imp=1, any=1, specific=1 dispatches');
    });
  });

  // T7 — a deal with no trackers serves NO field (absent, never [])
  scenario(report, 'T7', 'a creative without trackers has no thirdPartyTrackers field', (notes) async {
    await withDriver((d) async {
      final served = await decide(d,
          placements: [noTrackerPlacement],
          sessionId: freshSession('tpt_none'),
          configure: (b) => b.setUserId(freshUser('tpt_none')));
      final creative = served.creativeFor(noTrackerPlacement);
      check(creative != null, 'the no-tracker journey served');
      check(creative!.tracking.thirdPartyTrackers == null, 'model field is null');
      check(served.rawBody != null && !served.rawBody!.contains('thirdPartyTrackers'),
          'the field is ABSENT on the wire, not an empty array');
    });
  });

  // T8 — privacy: tracker URLs never reach the SDK's log sink
  scenario(report, 'T8', 'tracker URLs never appear in SDK logs', (notes) async {
    await withDriver((d) async {
      final creative =
          await decideUntilAd(d, classicPlacement, classicAdPublicId);
      d.sdk.fireImpression(creative.tracking);
      d.sdk.fireClick(creative.tracking, key: classicSpecificKey);
      await awaitWire(d, () => countSent(d, classicImpUrl) == 1);
      final offenders =
          d.logs.where((r) => r.message.contains(trackerHost)).toList();
      check(offenders.isEmpty,
          'no SDK log line contains the tracker host (found ${offenders.length})');
      notes.add('${d.logs.length} log records inspected, none carry tracker URLs');
    });
  });
}
