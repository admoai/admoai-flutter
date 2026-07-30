// ignore_for_file: avoid_print
@Tags(['e2e'])
library;

//
// Journey Ads — live, SDK-driven E2E runner (Flutter).
//
// Drives the **real** SDK against a **locally-running, seeded decision-engine**
// and asserts only what a customer's app can observe: the SDK result and the
// `/decision` transport. It is the Flutter counterpart of the Android
// `JourneyE2eRunner`, and exists because unit tests can only prove the SDK parses
// fixtures we wrote ourselves — they cannot prove the SDK and the engine agree.
//
// NOT part of the hermetic gate. Requires a local engine; run it with:
//
//   tool/journey_e2e.sh                     # wrapper: maps outcomes to exit codes
//   flutter test test/e2e/journey_e2e_test.dart --reporter expanded
//
// The deterministic offline gate excludes it:
//
//   flutter test --exclude-tags "live || e2e"
//
// Environment:
//   ADMOAI_JOURNEY_E2E_BASE_URL  default http://127.0.0.1:8080
//   ADMOAI_JOURNEY_E2E_VERSION   default 2025-11-01
//
// Requires: Statsig gate `is_journey_ads_enabled = true` (default OFF), Redis up,
// a 32-char TRACKING_KEY, mock seeds loaded into an empty DB, and VAST env vars
// for the video scenarios. Preflight proves the environment before asserting
// anything, so a broken environment is one diagnosis instead of N failures.
//
// See test/e2e/README.md for the design decisions and the SKIP-vs-FAIL contract.

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'journey_e2e_harness.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────
// The shipped demo journey. §B is bound to it rather than a dedicated
// `sdk_e2e_*` placement, which is why preflight proves its ownership.
const demoDefinition = 'ride_hailing_journey';
const demoStage1Placement = 'vehicleSelection'; // pre_ride, node 1
const demoStage1PlacementB = 'search'; // pre_ride, node 2 (multi-node)
const demoStage2Placement = 'journey'; // in_ride
const demoStage3Placement = 'rideSummary'; // post_ride
const demoStage1Key = 'pre_ride';
const demoStage2Key = 'in_ride';
const demoStage3Key = 'post_ride';

// Dedicated seeded fixtures. Each lives on its own `sdk_e2e_*` placement so
// priority tie-breaks can never mask the fixture under test.
const multiNodePlacements = [
  'sdk_e2e_multinode_a',
  'sdk_e2e_multinode_b',
  'sdk_e2e_multinode_c',
];

/// CPT deal with `custom_event` completion (`journey_complete` beacon) and
/// fallback `no_charge`. Its `standard` template carries a `destinationUrl`, so it
/// also drives the click-URL guard.
const cptCustomEventPlacement = 'sdk_e2e_cpt_completion';
const cptCustomEventKey = 'journey_complete';

/// Exact seeded values. Asserting the precise fallback mode matters: a non-blank
/// check passes on any wrong value, which is how a wrong billing mode could ship.
const cptPricingModel = 'cpt';
const cptCustomEventFallback = 'no_charge';
const cptFinalStageFallback = 'bill_per_stage';

/// CPT deal with `final_stage` completion pointing at the "complete" stage.
const cptFinalEarlyPlacement = 'sdk_e2e_cpt_final_early';
const cptFinalCompletePlacement = 'sdk_e2e_cpt_final_complete';

/// Frequency-capped journey: cap = 2 new instances per day, two nodes in one
/// stage so continuation can be told apart from admission.
const freqCapPlacement = 'sdk_e2e_frequency_cap';
const freqCapLaterPlacement = 'sdk_e2e_frequency_cap_later';
const freqCapAmount = 2;

/// Two-stage journey whose FIRST stage is `mandatory`.
const mandatoryEarlyPlacement = 'sdk_e2e_mandatory_early';
const mandatoryLaterPlacement = 'sdk_e2e_mandatory_later';

/// Two OPTIONAL stages on distinct placements — the contrast case to the
/// mandatory hold above.
const optSkipEarlyPlacement = 'sdk_e2e_optskip_early';
const optSkipLaterPlacement = 'sdk_e2e_optskip_later';

// Targeting fixtures, seeded at NYC with a 5000 m inclusive radius.
const targetGeoPlacement = 'sdk_e2e_target_geo';
const targetLocationPlacement = 'sdk_e2e_target_location';
const targetDestinationPlacement = 'sdk_e2e_target_destination';
const nycLatitude = 40.7128;
const nycLongitude = -74.006;
const nycGeonameId = 5128581;

/// A REAL geoname that simply does not match. `geoname_id = 1` is absent from the
/// engine's geoname set entirely, which makes the engine ERROR rather than
/// cleanly not-match — so a negative targeting case must use a real value.
const londonGeonameId = 2643743;
const londonLatitude = 51.5074;
const londonLongitude = -0.1278;

/// The deal's `dest_min_confidence`. A request at or above it matches.
const destinationThreshold = 0.7;

/// Journeys seeded with `runtime_state_ttl_seconds = 5`, applied verbatim as a
/// Redis `EX`. Short enough to wait out in a test.
const shortTtlPlacement = 'sdk_e2e_short_ttl';
const shortTtlSeconds = 5;

// Video journeys, one placement per delivery mode.
const videoJsonPlacement = 'sdk_e2e_video_json';
const videoVastTagPlacement = 'sdk_e2e_video_vast_tag';
const videoVastXmlPlacement = 'sdk_e2e_video_vast_xml';

// The hand-built wizard fixture (§K). Authored in the Ad Manager UI, NOT seeded,
// so `make db-reset` destroys it and §K then SKIPs. See fixtures/README.md.
const wizardDefinition = 'scooter_journey';
const wizardDeal = 'jad_01KYSSB2ND61HZFP3KRG9NET3X';
const wizardStage1 = 'pre_ride';
const wizardStage2 = 'post_ride';
const wizardStage3 = 'summary_ride';
const wizardPlacement1 = 'promotions';
const wizardPlacement2 = 'waiting';
const wizardPlacement3 = 'poi';

final report = E2eReport();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  hierarchicalLoggingEnabled = true;
  installPlatformChannelStubs();

  setUpAll(() async {
    print('Journey E2E → $e2eBaseUrl  (X-Decision-Version: $e2eApiVersion)');
    print('');
    await runPreflight();
  });

  tearDownAll(() {
    report.write();
    report.printSummary();
  });

  // Guards the Dart analogue of the Android runner's worst bug: a config hook
  // that silently drops the caller's user id and targeting looks exactly like an
  // engine defect. Proven on the wire, before any scenario relies on it.
  group('§Self-check', selfCheckGroup);

  // §K first, deliberately: it is the only platform-authored fixture, it cannot
  // be recreated from code, and one `make db-reset` destroys it.
  group('§K wizard parity', wizardParityGroup);

  group('§A request forwarding', requestForwardingGroup);
  group('§B progression & multi-node', progressionGroup);
  group('§C opt-in / opt-out', optGroup);
  group('§D tracking transport', trackingGroup);
  group('§E frequency cap', frequencyCapGroup);
  group('§H CPT & completion', completionGroup);
  group('§J mandatory/optional & targeting', targetingGroup);

  // Last: the most setup-heavy groups. §F spends real wall-clock waiting out a
  // 5-second runtime-state TTL.
  group('§F runtime-state TTL', ttlGroup);
  group('§G video delivery', videoGroup);
}

// ────────────────────────────────────────────────────────────────────────────
// Preflight — prove the environment is what we think it is.
//
// Android learned this the hard way: four scenarios "failed" for weeks of engine
// drift because local QA had left the demo deals inactive and a UI-created
// journey owned the shared placement. Not a regression. A preflight that names
// the offending definition turns four cryptic failures into one line.
// ────────────────────────────────────────────────────────────────────────────
Future<void> runPreflight() async {
  try {
    assertRealNetworkingEnabled();
    await withDriver((driver) async {
      // 1. Connectivity and version routing.
      final Served probe;
      try {
        probe = await decide(driver, placements: [demoStage1Placement]);
      } on NetworkError catch (error) {
        throw PreflightAbort(
          'cannot reach the decision-engine at $e2eBaseUrl (${error.message})',
          recipe: 'from the adhub root: `make start`',
        );
      } on APIError catch (error) {
        // Reachable but refusing the request — a different problem entirely, and
        // one that would otherwise read as "engine down".
        throw PreflightAbort(
          'the engine rejected a plain decision request: ${error.message}',
          recipe: 'check the engine logs and that the seeded placement '
              '"$demoStage1Placement" exists in this database',
        );
      }
      if (probe.statusCode != 200) {
        throw PreflightAbort(
          'engine returned HTTP ${probe.statusCode} for a plain decision',
          recipe: 'check the engine logs; `make start` from the adhub root',
        );
      }

      // 2. Do journeys serve at all? Catches the Statsig gate being off, Redis
      //    being down, and seeds never having loaded — all of which make the
      //    engine silently serve normal ads with no error to notice.
      final journeyProbe = await decide(
        driver,
        placements: [demoStage1Placement],
        sessionId: freshSession('preflight'),
        opt: JourneyOpt.optIn,
      );
      final creative = journeyProbe.creativeFor(demoStage1Placement);
      if (creative == null || !creative.isJourneyAd()) {
        throw PreflightAbort(
          'no journey served on "$demoStage1Placement" with a fresh session and '
          'journeyOpt=in — the engine is silently serving normal ads',
          recipe: 'check: Statsig `is_journey_ads_enabled = true` (default OFF), '
              'Redis up, mock seeds loaded (they load only into an EMPTY db), '
              'and X-Decision-Version = $e2eApiVersion',
        );
      }

      // 3. Is the demo placement owned by the definition we expect? A UI-created
      //    journey holding it makes §B unrunnable in a way that looks like an SDK
      //    or engine regression.
      final owner = creative.journeyDefinitionKey;
      if (owner != demoDefinition) {
        throw PreflightAbort(
          '"$demoStage1Placement" is owned by definition "$owner", expected '
          '"$demoDefinition" — local platform data is not a clean mock seed',
          recipe: 'WARNING: `make db-reset` from the adhub root fixes this but '
              'DESTROYS all locally-created platform data, including the '
              'hand-built §K wizard fixture. Deactivate the offending journey '
              'deal in the Ad Manager instead if you need §K to keep passing.',
        );
      }

      print('preflight OK — journeys serve, "$demoStage1Placement" owned by '
          '"$demoDefinition"');
      print('');
    });
  } on PreflightAbort catch (abort) {
    report.preflightDiagnosis = abort.diagnosis;
    report.preflightRecipe = abort.recipe;
    print('PREFLIGHT ABORT: ${abort.diagnosis}');
    if (abort.recipe != null) print('  fix: ${abort.recipe}');
    print('');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// §Self-check
// ────────────────────────────────────────────────────────────────────────────
void selfCheckGroup() {
  scenario(report, 'S1', 'the decide() helper forwards user id and targeting',
      (notes) async {
    await withDriver((driver) async {
      final userId = freshUser('selfcheck');
      final request = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage1Placement)
          .setUserId(userId)
          .addGeoTargeting(5128581)
          .build();
      final body = driver.sdk.getHttpRequest(request).body ?? '';

      check(body.contains('"id":"$userId"'),
          'the request body carries the user id set by the caller');
      check(body.contains('5128581'),
          'the request body carries the geo target set by the caller');
      notes.add('config forwarding proven on the wire');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §K — wizard parity.
//
// Every seeded fixture encodes what the ENGINE expects, so no seeded fixture can
// catch a mismatch between what the platform (Ad Manager) WRITES and what the
// engine READS. Both real bugs of the Android rounds lived in exactly that seam
// and both survived a fully green suite:
//   adhub #2459 — the wizard always persists a {"enabled":bool,"payload":{…}}
//     targeting envelope; the engine passed custom_targeting through raw, so
//     every wizard-created journey deal was dropped from every shortlist.
//   adhub #2483 — the platform writes camelCase template fields
//     (destinationUrl, urlSlide1..3) while the click resolver matched a
//     snake_case list, so tracking.clicks was [] on every journey serve.
// ────────────────────────────────────────────────────────────────────────────
void wizardParityGroup() {
  /// Probes the wizard fixture's first placement. Absence is an environment fact
  /// (a `db-reset` happened), so it SKIPs rather than FAILs — but a SKIP here
  /// means the platform→engine seam went unverified, which the summary calls out.
  Future<Creative> requireWizardServe(
    Driver driver,
    String sessionId,
    String placement,
  ) async {
    final served = await decide(
      driver,
      placements: [placement],
      sessionId: sessionId,
      opt: JourneyOpt.optIn,
    );
    final creative = served.creativeFor(placement);
    if (creative == null || !creative.isJourneyAd()) {
      throw SkipScenario(
        'no journey served on "$placement" — the hand-built "$wizardDefinition" '
        'fixture is absent (destroyed by `make db-reset`?). Rebuild it from '
        'test/e2e/fixtures/README.md, or the platform→engine seam is unverified.',
      );
    }
    if (creative.journeyDefinitionKey != wizardDefinition) {
      throw SkipScenario(
        '"$placement" is owned by "${creative.journeyDefinitionKey}", not the '
        'wizard fixture "$wizardDefinition" — another journey deal is masking it',
      );
    }
    return creative;
  }

  scenario(report, 'K1', 'platform-authored journey serves stage 1 with the '
      'config the wizard wrote, and exposes a click URL', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('k1');
      final creative =
          await requireWizardServe(driver, session, wizardPlacement1);

      check(creative.journeyDefinitionKey == wizardDefinition,
          'definitionKey is "$wizardDefinition"');
      check(creative.journeyDealId == wizardDeal,
          'dealId is the wizard deal $wizardDeal '
          '(got ${creative.journeyDealId})');
      check(creative.journeyStageKey == wizardStage1,
          'stageKey is "$wizardStage1" (got ${creative.journeyStageKey})');
      check((creative.journeyInstanceId ?? '').isNotEmpty,
          'an instance id was minted');
      check(creative.journeyPricingModel == 'cpt',
          'pricingModel is "cpt" (got ${creative.journeyPricingModel})');
      check(creative.journeyFallbackBillingMode == 'bill_per_stage',
          'fallbackBillingMode is "bill_per_stage" '
          '(got ${creative.journeyFallbackBillingMode})');
      check(creative.isJourneyCompletion == false,
          'stage 1 of a final_stage deal is not a completion');
      check(creative.journeySessionId == session,
          'the engine echoes the session id back');

      // The #2483 regression guard. The wizard writes camelCase url fields
      // (urlSlide1..3); if the click resolver ever stops matching them,
      // tracking.clicks silently becomes [] and journey CTR is unmeasurable —
      // with every other assertion here still green.
      final clickUrl = creative.tracking.getClickUrl();
      check(isTrackingUrl(clickUrl),
          'a click tracking URL is exposed and meets the transport contract '
          '(absolute, /v1/tracking, opaque ?e=) — got ${clickUrl ?? "none"}');
      final impressionUrl = creative.tracking.getImpressionUrl();
      check(isTrackingUrl(impressionUrl),
          'an impression tracking URL is exposed');

      notes.add('stage=${creative.journeyStageKey} '
          'node=${creative.journeyStageNodeId}');
      notes.add('clicks=${creative.tracking.clicks?.length ?? 0} '
          'impressions=${creative.tracking.impressions?.length ?? 0}');
    });
  });

  scenario(report, 'K2',
      'progression across platform-authored stages holds one instance',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('k2');
      final first =
          await requireWizardServe(driver, session, wizardPlacement1);

      final secondServed = await decide(
        driver,
        placements: [wizardPlacement2],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final second = secondServed.creativeFor(wizardPlacement2);
      check(second != null && second.isJourneyAd(),
          'stage 2 serves on "$wizardPlacement2"');

      check(second!.journeyInstanceId == first.journeyInstanceId,
          'the instance id is stable across stages '
          '(${first.journeyInstanceId} vs ${second.journeyInstanceId})');
      check(second.journeyDealId == first.journeyDealId,
          'the deal id is constant across the journey');
      check(second.journeyStageKey == wizardStage2,
          'stage advanced to "$wizardStage2" (got ${second.journeyStageKey})');
      check(second.journeyStageNodeId != first.journeyStageNodeId,
          'a different node served');
      check(second.isJourneyCompletion == false,
          'the middle stage is not the completion stage');

      notes.add('instance ${first.journeyInstanceId} held across '
          '$wizardStage1 → $wizardStage2');
    });
  });

  scenario(report, 'K3',
      "the wizard's final_stage completes the journey and emits no beacon",
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('k3');
      final first =
          await requireWizardServe(driver, session, wizardPlacement1);

      // Walk the graph to the completion stage.
      await decide(
        driver,
        placements: [wizardPlacement2],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final finalServed = await decide(
        driver,
        placements: [wizardPlacement3],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final last = finalServed.creativeFor(wizardPlacement3);
      check(last != null && last.isJourneyAd(),
          'the completion stage serves on "$wizardPlacement3"');

      check(last!.journeyStageKey == wizardStage3,
          'the served stage is "$wizardStage3" (got ${last.journeyStageKey})');
      check(last.journeyInstanceId == first.journeyInstanceId,
          'still the same instance at completion');
      check(last.isJourneyCompletion == true,
          'final_stage flips isCompletion to true');
      // The mirror assertion. final_stage and custom_event are mutually
      // exclusive per deal: completion is marked inline at decision time, so
      // there is nothing for the publisher to fire. A beacon here would mean
      // double counting.
      check(last.hasCompletionUrl == false,
          'a final_stage deal exposes NO completion beacon '
          '(got ${last.tracking.completions?.length ?? 0})');

      notes.add('completed on stage $wizardStage3, no beacon exposed');
    });
  });

  scenario(report, 'K4', 'an already-served wizard node does not serve twice',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('k4');
      final first =
          await requireWizardServe(driver, session, wizardPlacement1);
      final servedNode = first.journeyStageNodeId;

      final repeat = await decide(
        driver,
        placements: [wizardPlacement1],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final repeatCreative = repeat.creativeFor(wizardPlacement1);
      final repeatedSameNode = repeatCreative != null &&
          repeatCreative.isJourneyAd() &&
          repeatCreative.journeyStageNodeId == servedNode;
      check(!repeatedSameNode,
          'the same node does not serve twice (node $servedNode)');

      // Positive control. Without it, "no ad" is indistinguishable from "empty
      // placement" and the assertion above proves nothing. The control sends NO
      // session at all — omitting journeyOpt while sending a session is
      // effectively opt-in, which would start a journey and hold the surface,
      // so the control could never serve the competing ad. That mistake cost the
      // Android round a day.
      final control = await decide(driver, placements: [wizardPlacement1]);
      final controlCreative = control.creativeFor(wizardPlacement1);
      if (controlCreative == null) {
        notes.add('no competing normal ad on "$wizardPlacement1" — suppression '
            'is asserted without a positive control');
      } else {
        check(!controlCreative.isJourneyAd(),
            'the control (no session) serves a normal, non-journey ad, proving '
            '"$wizardPlacement1" has inventory and the no-ad above was takeover '
            'suppression rather than no-fill');
        notes.add('positive control served a normal ad '
            '(advertiser ${controlCreative.advertiser.name})');
      }

      final repeatIsNoAd = repeat.isNoAdFor(wizardPlacement1);
      notes.add(repeatIsNoAd
          ? 'repeat request returned no-ad'
          : 'repeat request served a different node '
              '(${repeatCreative?.journeyStageNodeId})');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §A — request forwarding & backward compatibility
// ────────────────────────────────────────────────────────────────────────────
void requestForwardingGroup() {
  scenario(report, 'A1',
      'no sessionId → a normal decision with no journey metadata', (notes) async {
    await withDriver((driver) async {
      // Journeys cannot activate without a publisher-supplied session. This is
      // the safe default: an integration that forgets sessionId keeps serving
      // normal ads rather than breaking.
      final served = await decide(driver, placements: [demoStage1Placement]);
      final creative = served.creativeFor(demoStage1Placement);
      check(creative != null, 'a normal ad served on "$demoStage1Placement"');

      check(!creative!.isJourneyAd(), 'the serve is not a journey ad');
      check(creative.journeyInstanceId == null, 'no instance id is exposed');
      check(creative.journeyDealId == null, 'no deal id is exposed');
      check(creative.journeyStageKey == null, 'no stage key is exposed');
      check(creative.isJourneyCompletion == false, 'isCompletion is false');
      check(creative.hasCompletionUrl == false, 'no completion beacon');
      notes.add('normal ad from advertiser ${creative.advertiser.name}');
    });
  });

  scenario(report, 'A3',
      'sessionId/journeyOpt reach the wire top-level and camelCase, with the '
      'version header', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('a3');
      final request = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage1Placement)
          .setSessionId(session)
          .setJourneyOpt(JourneyOpt.optIn)
          .build();
      final http = driver.sdk.getHttpRequest(request);
      final body = http.body ?? '';

      check(http.headers?['X-Decision-Version'] == e2eApiVersion,
          'X-Decision-Version is $e2eApiVersion — without it the engine '
          'SILENTLY ignores journey fields and serves normal ads');
      check(body.contains('"sessionId":"$session"'),
          'sessionId is a top-level camelCase field');
      check(body.contains('"journeyOpt":"in"'),
          'journeyOpt serializes as the wire literal "in"');
      // Not nested under user/targeting — a shape mismatch the engine would
      // ignore without complaining.
      check(!body.contains('"user":{"sessionId"'),
          'sessionId is not nested under user');
      notes.add('wire shape verified without touching the engine');
    });
  });

  scenario(report, 'A4', 'sessionId is sticky across builds and not regenerated',
      (notes) async {
    final session = freshSession('a4');
    await withDriver(sessionId: session, (driver) async {
      // Every builder inherits the sticky value, and rebuilding never mints a
      // new one — the SDK must never generate, rotate or persist a session id.
      final first = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage1Placement)
          .build();
      final second = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage2Placement)
          .build();

      check(first.sessionId == session, 'the first builder inherited it');
      check(second.sessionId == session, 'the second builder inherited it too');

      // A per-request override applies to that request only.
      final override = freshSession('a4-override');
      final third = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage1Placement)
          .setSessionId(override)
          .build();
      final fourth = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage1Placement)
          .build();
      check(third.sessionId == override, 'the per-request override applies');
      check(fourth.sessionId == session,
          'the override did not leak into the next request');

      // And a per-request clear removes it for that request only.
      final cleared = driver.sdk
          .createRequestBuilder()
          .addPlacement(key: demoStage1Placement)
          .clearSessionId()
          .build();
      check(cleared.sessionId == null, 'a per-request clear drops the session');
      notes.add('sticky, overridable, and clearable per request');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §B — stage progression & multi-node (shipped demo ride-hailing journey)
//
// This is the only group bound to the shipped demo fixture on shared demo
// placements rather than a dedicated `sdk_e2e_*` placement, which is why
// preflight proves ownership before any of it runs.
// ────────────────────────────────────────────────────────────────────────────
void progressionGroup() {
  /// Serves the journey's first stage and returns the creative.
  Future<Creative> startJourney(Driver driver, String session) async {
    final served = await decide(
      driver,
      placements: [demoStage1Placement],
      sessionId: session,
      opt: JourneyOpt.optIn,
    );
    final creative = served.creativeFor(demoStage1Placement);
    check(creative != null && creative.isJourneyAd(),
        'the journey starts on "$demoStage1Placement"');
    return creative!;
  }

  scenario(report, 'B1', 'a new session serves the first stage and starts an '
      'instance', (notes) async {
    await withDriver((driver) async {
      final creative = await startJourney(driver, freshSession('b1'));

      check(creative.journeyDefinitionKey == demoDefinition,
          'definitionKey is "$demoDefinition"');
      check(creative.journeyStageKey == demoStage1Key,
          'the first stage "$demoStage1Key" serves '
          '(got ${creative.journeyStageKey})');
      check((creative.journeyInstanceId ?? '').isNotEmpty,
          'a non-blank instance id was minted');
      check(creative.isJourneyCompletion != true,
          'the first stage is not a completion');
      notes.add('instance ${creative.journeyInstanceId} '
          'stage ${creative.journeyStageKey}');
    });
  });

  scenario(report, 'B2', 'a second node in the same stage serves (multi-node)',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('b2');
      final first = await startJourney(driver, session);

      final served = await decide(
        driver,
        placements: [demoStage1PlacementB],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final second = served.creativeFor(demoStage1PlacementB);
      check(second != null && second.isJourneyAd(),
          'the second node serves on "$demoStage1PlacementB"');

      check(second!.journeyStageKey == first.journeyStageKey,
          'the stage did not advance (still ${first.journeyStageKey})');
      check(second.journeyStageNodeId != first.journeyStageNodeId,
          'a different node served');
      check(second.journeyInstanceId == first.journeyInstanceId,
          'the same instance served both nodes');
      notes.add('nodes ${first.journeyStageNodeId} + '
          '${second.journeyStageNodeId} in ${first.journeyStageKey}');
    });
  });

  scenario(report, 'B3', 'a repeated node returns no-ad; a positive control '
      'proves suppression rather than no-fill', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('b3');
      final first = await startJourney(driver, session);

      final repeat = await decide(
        driver,
        placements: [demoStage1Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final repeatCreative = repeat.creativeFor(demoStage1Placement);
      final sameNodeAgain = repeatCreative != null &&
          repeatCreative.isJourneyAd() &&
          repeatCreative.journeyStageNodeId == first.journeyStageNodeId;
      check(!sameNodeAgain, 'the already-served node does not serve again');

      // The control sends NO session. Sending a session with journeyOpt omitted
      // is effectively opt-in, so the control would start its own journey and
      // hold the surface — and could never serve the competing ad.
      final control = await decide(driver, placements: [demoStage1Placement]);
      final controlCreative = control.creativeFor(demoStage1Placement);
      check(controlCreative != null && !controlCreative.isJourneyAd(),
          'the no-session control serves a competing normal ad, proving the '
          'placement has inventory and the no-ad above was takeover '
          'suppression, not a fill failure');
      notes.add('control advertiser ${controlCreative!.advertiser.name}');
    });
  });

  scenario(report, 'B4', 'the next stage serves with a stable instance',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('b4');
      final first = await startJourney(driver, session);

      final served = await decide(
        driver,
        placements: [demoStage2Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final second = served.creativeFor(demoStage2Placement);
      check(second != null && second.isJourneyAd(),
          'stage 2 serves on "$demoStage2Placement"');

      check(second!.journeyStageKey == demoStage2Key,
          'the stage advanced to "$demoStage2Key" '
          '(got ${second.journeyStageKey})');
      check(second.journeyInstanceId == first.journeyInstanceId,
          'the instance id is stable across '
          '$demoStage1Key → $demoStage2Key');
      notes.add('instance ${first.journeyInstanceId} held across stages');
    });
  });

  scenario(report, 'B5', 'the final stage serves', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('b5');
      final first = await startJourney(driver, session);
      await decide(
        driver,
        placements: [demoStage2Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final served = await decide(
        driver,
        placements: [demoStage3Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final last = served.creativeFor(demoStage3Placement);
      check(last != null && last.isJourneyAd(),
          'the final stage serves on "$demoStage3Placement"');

      check(last!.journeyStageKey == demoStage3Key,
          'the stage advanced to "$demoStage3Key" (got ${last.journeyStageKey})');
      check(last.journeyInstanceId == first.journeyInstanceId,
          'still the same instance');
      // Recorded rather than over-asserted: whether the last stage completes
      // depends on the deal's completion configuration, which is the engine's
      // business, not the SDK's.
      notes.add('isCompletion=${last.isJourneyCompletion} '
          'pricing=${last.journeyPricingModel}');
    });
  });

  scenario(report, 'B6', 'three nodes in one stage each serve exactly once',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('b6');
      final seen = <String>[];
      String? instance;
      String? stageKey;

      for (final placement in multiNodePlacements) {
        final served = await decide(
          driver,
          placements: [placement],
          sessionId: session,
          opt: JourneyOpt.optIn,
        );
        final creative = served.creativeFor(placement);
        if (creative == null || !creative.isJourneyAd()) {
          throw SkipScenario(
            'the seeded multi-node fixture did not serve on "$placement" — '
            'is `e2e_multinode_journey` present in this database?',
          );
        }
        instance ??= creative.journeyInstanceId;
        stageKey ??= creative.journeyStageKey;
        check(creative.journeyInstanceId == instance,
            'every node served under the same instance');
        check(creative.journeyStageKey == stageKey,
            'the stage never regresses or advances (still $stageKey)');
        check(!seen.contains(creative.journeyStageNodeId),
            'node ${creative.journeyStageNodeId} served only once');
        seen.add(creative.journeyStageNodeId ?? '');
      }

      check(seen.length == 3, 'all three nodes served');
      check(seen.toSet().length == 3, 'the three node ids are distinct');
      notes.add('stage $stageKey served nodes ${seen.join(", ")}');
    });
  });

  scenario(report, 'B7', 'journey metadata is coherent and echoes the request',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('b7');
      final first = await startJourney(driver, session);

      // Guards the tolerant-reader mapping. If one field silently decodes to
      // null, every other scenario stays green — this is the scenario that
      // notices.
      check(first.journeySessionId == session,
          'the engine echoes the session id back '
          '(got ${first.journeySessionId})');
      check(first.journeyOptStatus == JourneyOpt.optIn,
          'optStatus echoes the opt-in (got ${first.journeyOptStatus})');
      check((first.journeyStageId ?? '').isNotEmpty, 'stageId is surfaced');
      check((first.journeyStageNodeId ?? '').isNotEmpty,
          'stageNodeId is surfaced');
      check((first.journeyDealId ?? '').isNotEmpty, 'dealId is surfaced');
      check((first.journeyPricingModel ?? '').isNotEmpty,
          'pricingModel is surfaced');

      // The render-level attribution key, which the engine mints per served
      // creative and emits on EVERY journey serve. This SDK dropped it silently
      // for the whole feature's life: the Tolerant Reader discards unknown fields
      // by design, and nothing here had ever asserted anything about `metadata`,
      // so every journey-block assertion above stayed green while a field iOS and
      // Android both expose went missing. Asserted live, because the engine is the
      // only thing that can prove it is actually sent.
      check(first.metadata != null,
          'the serve carries a metadata block');
      check((first.metadata!.impId ?? '').isNotEmpty,
          'metadata.impId is surfaced on a journey serve '
          '(got ${first.metadata!.impId ?? "null"})');

      final second = await decide(
        driver,
        placements: [demoStage2Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final next = second.creativeFor(demoStage2Placement);
      check(next != null && next.isJourneyAd(), 'stage 2 serves');
      check(next!.journeyDealId == first.journeyDealId,
          'dealId is constant across the journey stages');
      check(next.journeySessionId == session,
          'the session id is echoed on every serve');
      notes.add('deal ${first.journeyDealId} stable; sessionId echoed; '
          'impId ${first.metadata?.impId}');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §C — opt-in / opt-out
// ────────────────────────────────────────────────────────────────────────────
void optGroup() {
  scenario(report, 'C1', 'opt-out before any serve → no journey', (notes) async {
    await withDriver((driver) async {
      final served = await decide(
        driver,
        placements: [demoStage1Placement],
        sessionId: freshSession('c1'),
        opt: JourneyOpt.optOut,
      );
      final creative = served.creativeFor(demoStage1Placement);
      check(creative != null, 'a normal ad serves instead');
      check(!creative!.isJourneyAd(),
          'opt-out suppresses the journey entirely — note that OMITTING '
          'journeyOpt would be permissive and start one');
      notes.add('opt-out fell back to a normal ad '
          '(${creative.advertiser.name})');
    });
  });

  scenario(report, 'C2/C3',
      'opt-out closes the instance; a later opt-in mints a NEW instance',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('c2');
      final first = await decide(
        driver,
        placements: [demoStage1Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final started = first.creativeFor(demoStage1Placement);
      check(started != null && started.isJourneyAd(), 'a journey started');
      final firstInstance = started!.journeyInstanceId;

      // Opt-out ENDS the journey rather than pausing it.
      final optedOut = await decide(
        driver,
        placements: [demoStage2Placement],
        sessionId: session,
        opt: JourneyOpt.optOut,
      );
      final optedOutCreative = optedOut.creativeFor(demoStage2Placement);
      check(optedOutCreative == null || !optedOutCreative.isJourneyAd(),
          'no journey serves while opted out');

      // Opting back in cannot resume the closed instance — it starts a new one.
      final rejoined = await decide(
        driver,
        placements: [demoStage1Placement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final rejoinedCreative = rejoined.creativeFor(demoStage1Placement);
      check(rejoinedCreative != null && rejoinedCreative.isJourneyAd(),
          'a journey serves again after opting back in');
      check(rejoinedCreative!.journeyInstanceId != firstInstance,
          'the new instance id differs from the closed one '
          '($firstInstance → ${rejoinedCreative.journeyInstanceId})');
      notes.add('instance $firstInstance closed; '
          '${rejoinedCreative.journeyInstanceId} minted');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §D — tracking transport (black-box)
//
// Identity lives inside the encrypted `?e=` token, which is server-owned. The
// SDK must not, and does not, parse it — so these assertions are about transport
// shape and byte-exact firing, never about token contents.
// ────────────────────────────────────────────────────────────────────────────
void trackingGroup() {
  /// Serves the dedicated CPT fixture, whose `standard` template carries a
  /// `destinationUrl` — so it exposes both an impression and a click beacon.
  Future<Creative> serveTrackable(Driver driver, String session) async {
    final served = await decide(
      driver,
      placements: [cptCustomEventPlacement],
      sessionId: session,
      opt: JourneyOpt.optIn,
    );
    final creative = served.creativeFor(cptCustomEventPlacement);
    if (creative == null || !creative.isJourneyAd()) {
      throw SkipScenario(
        'the seeded fixture did not serve on "$cptCustomEventPlacement" — is '
        '`e2e_cpt_journey` present in this database?',
      );
    }
    return creative;
  }

  scenario(report, 'D1',
      'tracking URLs are absolute /v1/tracking with an opaque ?e= token',
      (notes) async {
    await withDriver((driver) async {
      final creative = await serveTrackable(driver, freshSession('d1'));
      final impression = creative.tracking.getImpressionUrl();

      check(isTrackingUrl(impression),
          'the impression URL is absolute, path /v1/tracking, with a non-empty '
          '?e= token (got ${impression ?? "none"})');
      final uri = Uri.parse(impression!);
      check(uri.queryParameters['e']!.length > 20,
          'the token is opaque, not a readable identifier');
      notes.add('${uri.scheme}://${uri.authority}${uri.path} '
          '?e=<${uri.queryParameters['e']!.length} chars>');
    });
  });

  scenario(report, 'D5',
      'a journey creative with a destination exposes a click URL', (notes) async {
    // Regression guard for adhub #2483: the platform writes camelCase template
    // fields while the click resolver matched a snake_case list, so
    // tracking.clicks was [] on EVERY journey serve for weeks. The suite stayed
    // green the whole time because §D asserted impressions only. An assertion
    // that was never written is indistinguishable from a passing one.
    await withDriver((driver) async {
      final creative = await serveTrackable(driver, freshSession('d5'));
      final click = creative.tracking.getClickUrl();

      check(isTrackingUrl(click),
          'a click tracking URL is exposed and meets the same transport '
          'contract as the impression (got ${click ?? "none"})');
      check(click != creative.tracking.getImpressionUrl(),
          'the click beacon is distinct from the impression beacon');
      notes.add('clicks=${creative.tracking.clicks?.length ?? 0}');
    });
  });

  scenario(report, 'D2',
      'the SDK fires the URL verbatim and a retry re-fires it identically',
      (notes) async {
    await withDriver((driver) async {
      final creative = await serveTrackable(driver, freshSession('d2'));
      final impression = creative.tracking.getImpressionUrl()!;

      driver.client.sent.clear();
      driver.sdk.fireImpression(creative.tracking);
      await Future.delayed(const Duration(milliseconds: 400));
      driver.sdk.fireImpression(creative.tracking);
      await Future.delayed(const Duration(milliseconds: 400));

      final fired =
          driver.client.sent.where((u) => u.contains('/v1/tracking')).toList();
      check(fired.length == 2, 'both fires reached the transport');
      check(fired[0] == impression,
          'the URL was fired byte-identical to what the engine returned');
      check(fired[0] == fired[1], 'the retry re-fired the identical string');
      // Fire-and-forget: locally the engine mints https:// URLs while serving
      // plaintext, so the request itself fails the TLS handshake. It must never
      // surface to the caller.
      notes.add('fired verbatim twice; failures stayed inside the SDK');
    });
  });

  scenario(report, 'D4', 'a no-ad response exposes no tracking and fires nothing',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('d4');
      await serveTrackable(driver, session); // consume the only node

      final repeat = await decide(
        driver,
        placements: [cptCustomEventPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final decision = repeat.decisionFor(cptCustomEventPlacement);
      if (decision == null || decision.hasCreative) {
        throw SkipScenario(
          'expected a no-ad on the repeat request but a creative served — the '
          'fixture may have more than one node on this placement',
        );
      }

      check(decision.isNoAd, 'the decision is a clean no-ad');
      check(decision.creatives == null || decision.creatives!.isEmpty,
          'creatives is empty or absent — both shapes mean the same thing');

      driver.client.sent.clear();
      // There is no creative, so there is no tracking to fire. Nothing is ever
      // fired automatically, so this is a no-op by construction.
      await Future.delayed(const Duration(milliseconds: 200));
      check(driver.client.sent.isEmpty, 'no tracking request was made');
      notes.add('no-ad exposed no creative and fired nothing');
    });
  });

  scenario(report, 'D6', 'the engine accepts a tracking token it minted itself',
      (notes) async {
    await withDriver((driver) async {
      final creative = await serveTrackable(driver, freshSession('d6'));
      final minted = creative.tracking.getImpressionUrl()!;

      // Local-only artifact: the engine mints production-shaped https:// URLs
      // while serving plaintext on :8080, so firing one verbatim fails the TLS
      // handshake locally. Scheme/host/port are normalized onto the configured
      // base URL and the ?e= token is left untouched — rewriting the token would
      // invalidate the very thing being tested.
      final normalized = normalizeForLocalIngestion(minted);
      check(Uri.parse(normalized).queryParameters['e'] ==
              Uri.parse(minted).queryParameters['e'],
          'normalization left the opaque token untouched');

      final client = http.Client();
      try {
        final response = await client
            .get(Uri.parse(normalized))
            .timeout(const Duration(seconds: 15));
        check(response.statusCode >= 200 && response.statusCode < 300,
            'the tracking endpoint accepted the token it minted '
            '(got HTTP ${response.statusCode})');
        notes.add('ingestion returned HTTP ${response.statusCode}');
      } finally {
        client.close();
      }
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §E — frequency cap
//
// The cap is a Redis sorted set counting NEW instances per user+deal. It never
// blocks continuation of an active instance, and it is skipped entirely when
// `user.id` is absent — so every scenario here must set a user id, and it must be
// unique per run or the cap keys collide across runs and the suite is a one-shot.
// ────────────────────────────────────────────────────────────────────────────
void frequencyCapGroup() {
  scenario(report, 'E1', 'new-entry capping gates deterministically at the '
      'configured amount', (notes) async {
    await withDriver((driver) async {
      final userId = freshUser('e1');
      final admitted = <String>[];

      // Each attempt is a brand-new session, so each is a new-instance
      // admission — the only thing the cap counts. Deterministic: it depends on
      // the count, not on wall-clock.
      for (var attempt = 1; attempt <= freqCapAmount + 1; attempt++) {
        final served = await decide(
          driver,
          placements: [freqCapPlacement],
          sessionId: freshSession('e1_$attempt'),
          opt: JourneyOpt.optIn,
          configure: (builder) => builder.setUserId(userId),
        );
        final creative = served.creativeFor(freqCapPlacement);
        if (attempt == 1 && (creative == null || !creative.isJourneyAd())) {
          throw SkipScenario(
            'the seeded frequency-cap fixture did not serve on '
            '"$freqCapPlacement" — is `e2e_frequency_cap_journey` present?',
          );
        }
        if (creative != null && creative.isJourneyAd()) {
          admitted.add(creative.journeyInstanceId ?? '');
        }
      }

      check(admitted.length == freqCapAmount,
          'exactly $freqCapAmount new instances were admitted and the next was '
          'refused (got ${admitted.length})');
      check(admitted.toSet().length == freqCapAmount,
          'each admission minted a distinct instance');
      notes.add('cap $freqCapAmount honoured for user $userId');
    });
  });

  scenario(report, 'E2', 'the cap never blocks continuation of an active '
      'instance', (notes) async {
    await withDriver((driver) async {
      final userId = freshUser('e2');
      final liveSession = freshSession('e2_live');

      // Admission 1 — the instance we will later continue.
      final first = await decide(
        driver,
        placements: [freqCapPlacement],
        sessionId: liveSession,
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.setUserId(userId),
      );
      final started = first.creativeFor(freqCapPlacement);
      if (started == null || !started.isJourneyAd()) {
        throw SkipScenario(
          'the seeded frequency-cap fixture did not serve on '
          '"$freqCapPlacement" — is `e2e_frequency_cap_journey` present?',
        );
      }
      final liveInstance = started.journeyInstanceId;

      // Exhaust the remaining admissions with throwaway sessions.
      for (var i = 0; i < freqCapAmount; i++) {
        await decide(
          driver,
          placements: [freqCapPlacement],
          sessionId: freshSession('e2_fill_$i'),
          opt: JourneyOpt.optIn,
          configure: (builder) => builder.setUserId(userId),
        );
      }

      // A brand-new instance is now refused...
      final refused = await decide(
        driver,
        placements: [freqCapPlacement],
        sessionId: freshSession('e2_refused'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.setUserId(userId),
      );
      final refusedCreative = refused.creativeFor(freqCapPlacement);
      check(refusedCreative == null || !refusedCreative.isJourneyAd(),
          'a brand-new instance is refused once the cap is exhausted');

      // ...while the already-active instance still progresses.
      final continued = await decide(
        driver,
        placements: [freqCapLaterPlacement],
        sessionId: liveSession,
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.setUserId(userId),
      );
      final continuation = continued.creativeFor(freqCapLaterPlacement);
      check(continuation != null && continuation.isJourneyAd(),
          'the active instance still serves its next node with the cap '
          'exhausted');
      check(continuation!.journeyInstanceId == liveInstance,
          'it is the same instance, not a new admission '
          '($liveInstance vs ${continuation.journeyInstanceId})');
      notes.add('instance $liveInstance continued past an exhausted cap');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §H — CPT pricing and the two completion strategies
//
// The strategies are mutually exclusive per deal:
//   custom_event → every served node exposes a completions[] beacon and
//     isCompletion stays FALSE. Completion records only when the publisher fires
//     it — this is what bills CPT.
//   final_stage  → isCompletion is TRUE on any served node of the completion
//     stage, marked inline at decision time, and there is NO beacon.
// ────────────────────────────────────────────────────────────────────────────
void completionGroup() {
  scenario(report, 'H1/H2', 'a CPT deal surfaces the exact pricing model and '
      'fallback billing mode', (notes) async {
    await withDriver((driver) async {
      final served = await decide(
        driver,
        placements: [cptCustomEventPlacement],
        sessionId: freshSession('h1'),
        opt: JourneyOpt.optIn,
      );
      final creative = served.creativeFor(cptCustomEventPlacement);
      if (creative == null || !creative.isJourneyAd()) {
        throw SkipScenario(
          'the seeded CPT fixture did not serve on "$cptCustomEventPlacement" '
          '— is `e2e_cpt_journey` present?',
        );
      }

      // Asserted exactly, not just non-blank: the old non-blank check passed on
      // any wrong value, which is how a wrong billing mode ships unnoticed.
      check(creative.journeyPricingModel == cptPricingModel,
          'pricingModel is "$cptPricingModel" '
          '(got ${creative.journeyPricingModel})');
      check(creative.journeyFallbackBillingMode == cptCustomEventFallback,
          'fallbackBillingMode is exactly "$cptCustomEventFallback" '
          '(got ${creative.journeyFallbackBillingMode})');
      notes.add('${creative.journeyPricingModel} / '
          '${creative.journeyFallbackBillingMode}');
    });
  });

  scenario(report, 'H5', 'a custom_event CPT deal exposes a fireable completion '
      'beacon while isCompletion stays false', (notes) async {
    // The CPT billing trigger, and shipped public API. On Android this surface
    // had ZERO coverage: hasCompletionUrl()/fireCompletion() were exercised by
    // nothing at all, so a break would have been invisible.
    await withDriver((driver) async {
      final served = await decide(
        driver,
        placements: [cptCustomEventPlacement],
        sessionId: freshSession('h5'),
        opt: JourneyOpt.optIn,
      );
      final creative = served.creativeFor(cptCustomEventPlacement);
      if (creative == null || !creative.isJourneyAd()) {
        throw SkipScenario(
          'the seeded CPT fixture did not serve on "$cptCustomEventPlacement" '
          '— is `e2e_cpt_journey` present?',
        );
      }

      check(creative.hasCompletionUrl,
          'the served node exposes a completions[] beacon');
      final completionUrl =
          creative.tracking.getCompletionUrl(key: cptCustomEventKey);
      check(isTrackingUrl(completionUrl),
          'the beacon is keyed "$cptCustomEventKey" and meets the transport '
          'contract (got ${completionUrl ?? "none"})');
      check(creative.isJourneyCompletion == false,
          'isCompletion stays FALSE for custom_event — completion is recorded '
          'only when the publisher fires the beacon');

      // Additive to the normal impression, never a replacement.
      check(isTrackingUrl(creative.tracking.getImpressionUrl()),
          'the normal impression beacon is still present alongside it');

      driver.client.sent.clear();
      driver.sdk.fireCompletion(creative.tracking, key: cptCustomEventKey);
      await Future.delayed(const Duration(milliseconds: 400));
      final fired = driver.client.sent
          .where((u) => u.contains('/v1/tracking'))
          .toList();
      check(fired.length == 1, 'fireCompletion dispatched exactly one request');
      check(fired.single == completionUrl,
          'it fired the server-provided URL verbatim');
      notes.add('beacon "$cptCustomEventKey" exposed and fired verbatim');
    });
  });

  scenario(report, 'H3', 'a final_stage serve flips isCompletion and emits NO '
      'beacon', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('h3');
      final early = await decide(
        driver,
        placements: [cptFinalEarlyPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final earlyCreative = early.creativeFor(cptFinalEarlyPlacement);
      if (earlyCreative == null || !earlyCreative.isJourneyAd()) {
        throw SkipScenario(
          'the seeded final_stage fixture did not serve on '
          '"$cptFinalEarlyPlacement" — is `e2e_cpt_final_journey` present?',
        );
      }
      check(earlyCreative.isJourneyCompletion == false,
          'the earlier stage is not the completion stage');

      final complete = await decide(
        driver,
        placements: [cptFinalCompletePlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final completion = complete.creativeFor(cptFinalCompletePlacement);
      check(completion != null && completion.isJourneyAd(),
          'the completion stage serves on "$cptFinalCompletePlacement"');

      check(completion!.isJourneyCompletion == true,
          'final_stage flips isCompletion to true, inline at decision time');
      check(completion.hasCompletionUrl == false,
          'and emits NO completion beacon — there is nothing for the publisher '
          'to fire, so a beacon here would mean double counting '
          '(got ${completion.tracking.completions?.length ?? 0})');
      check(completion.journeyPricingModel == cptPricingModel,
          'CPT pricing is surfaced on the completing serve');
      check(completion.journeyFallbackBillingMode == cptFinalStageFallback,
          'fallbackBillingMode is exactly "$cptFinalStageFallback" '
          '(got ${completion.journeyFallbackBillingMode})');
      notes.add('completed inline; beacons=0; '
          '${completion.journeyPricingModel}/'
          '${completion.journeyFallbackBillingMode}');
    });
  });

  scenario(report, 'H4', 'after completion, takeover protection ends',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('h4');
      await decide(
        driver,
        placements: [cptFinalEarlyPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final complete = await decide(
        driver,
        placements: [cptFinalCompletePlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final completion = complete.creativeFor(cptFinalCompletePlacement);
      if (completion == null || completion.isJourneyCompletion != true) {
        throw SkipScenario(
          'could not reach the completion stage on '
          '"$cptFinalCompletePlacement" — is `e2e_cpt_final_journey` present?',
        );
      }

      // The corrected assertion. A completed instance is TERMINAL: a continued
      // OPT-IN mints a brand-new instance (opt-in means "give me a journey"),
      // so only OPT-OUT reveals that the takeover has ended. The original
      // Android test assumed "after completion ⇒ normal ad" under opt-in and was
      // wrong; the engine was right.
      final after = await decide(
        driver,
        placements: [cptFinalCompletePlacement],
        sessionId: session,
        opt: JourneyOpt.optOut,
      );
      final normal = after.creativeFor(cptFinalCompletePlacement);
      check(normal != null,
          'a competing normal ad serves on the completion placement once the '
          'takeover has ended');
      check(!normal!.isJourneyAd(), 'and it is not a journey ad');
      notes.add('takeover ended; normal ad from ${normal.advertiser.name}');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §J — mandatory vs optional stages, and targeting in both directions
// ────────────────────────────────────────────────────────────────────────────
void targetingGroup() {
  scenario(report, 'J1', 'an unserved mandatory stage HOLDS the later surface',
      (notes) async {
    await withDriver((driver) async {
      // Requesting the later stage while the mandatory earlier stage is unserved
      // must produce a no-ad hold rather than letting a competitor in.
      final held = await decide(
        driver,
        placements: [mandatoryLaterPlacement],
        sessionId: freshSession('j1'),
        opt: JourneyOpt.optIn,
      );
      final heldCreative = held.creativeFor(mandatoryLaterPlacement);

      // Positive control FIRST, so a missing fixture cannot masquerade as a hold.
      // No session at all — a session with journeyOpt omitted is effectively
      // opt-in and would start a journey that holds the surface itself.
      final control = await decide(driver, placements: [mandatoryLaterPlacement]);
      final controlCreative = control.creativeFor(mandatoryLaterPlacement);
      if (controlCreative == null) {
        throw SkipScenario(
          'no competing control ad on "$mandatoryLaterPlacement" — without one, '
          'a no-ad is indistinguishable from an empty placement and proves '
          'nothing. Is `e2e_mandatory_journey` and its control ad seeded?',
        );
      }
      check(!controlCreative.isJourneyAd(),
          'the no-session control serves a competing normal ad, proving the '
          'placement has inventory');

      check(heldCreative == null || !heldCreative.isJourneyAd(),
          'the later optional stage did not serve while the mandatory stage is '
          'unserved');
      check(heldCreative == null,
          'the surface is HELD — no competing ad served either, which is '
          'correct takeover behaviour and not a fill failure');
      notes.add('mandatory hold confirmed against a serving control');
    });
  });

  scenario(report, 'J5', 'an optional stage with no node on the requested '
      'placement is SKIPPED and cannot serve later', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('j5');

      // Requesting the LATER placement means the earlier optional stage has no
      // node for this request, so the engine skips it. Contrast with J1, where
      // the earlier stage is mandatory and holds instead. The skip lever is
      // placement availability, not creative absence: a node that merely lacks a
      // creative "phantom-serves" and closes the whole instance.
      final later = await decide(
        driver,
        placements: [optSkipLaterPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final laterCreative = later.creativeFor(optSkipLaterPlacement);
      if (laterCreative == null || !laterCreative.isJourneyAd()) {
        throw SkipScenario(
          'the later optional stage did not serve on "$optSkipLaterPlacement" '
          '— is `e2e_optional_skip_journey` present?',
        );
      }

      final earlier = await decide(
        driver,
        placements: [optSkipEarlyPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final earlierCreative = earlier.creativeFor(optSkipEarlyPlacement);
      check(earlierCreative == null || !earlierCreative.isJourneyAd(),
          'the skipped stage cannot serve afterwards — the journey never goes '
          'backwards');
      notes.add('stage ${laterCreative.journeyStageKey} served; '
          'the earlier stage stayed skipped');
    });
  });

  scenario(report, 'J4',
      'geo targeting: a matching geoname serves, a real non-matching one does not',
      (notes) async {
    await withDriver((driver) async {
      final match = await decide(
        driver,
        placements: [targetGeoPlacement],
        sessionId: freshSession('j4_match'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.addGeoTargeting(nycGeonameId),
      );
      final matched = match.creativeFor(targetGeoPlacement);
      if (matched == null || !matched.isJourneyAd()) {
        throw SkipScenario(
          'the geo-targeted fixture did not serve for geoname $nycGeonameId on '
          '"$targetGeoPlacement" — is `e2e_target_geo_journey` present?',
        );
      }

      final noMatch = await decide(
        driver,
        placements: [targetGeoPlacement],
        sessionId: freshSession('j4_nomatch'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.addGeoTargeting(londonGeonameId),
      );
      final unmatched = noMatch.creativeFor(targetGeoPlacement);
      check(unmatched == null || !unmatched.isJourneyAd(),
          'a real but non-matching geoname ($londonGeonameId) excludes the deal '
          'cleanly, rather than erroring');
      notes.add('geo $nycGeonameId served; $londonGeonameId excluded');
    });
  });

  scenario(report, 'J2',
      'location targeting: inside the radius serves, outside does not',
      (notes) async {
    await withDriver((driver) async {
      final inside = await decide(
        driver,
        placements: [targetLocationPlacement],
        sessionId: freshSession('j2_in'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.addLocationTargeting(
          latitude: nycLatitude,
          longitude: nycLongitude,
        ),
      );
      final insideCreative = inside.creativeFor(targetLocationPlacement);
      if (insideCreative == null || !insideCreative.isJourneyAd()) {
        throw SkipScenario(
          'the location-targeted fixture did not serve in-radius on '
          '"$targetLocationPlacement" — is `e2e_target_location_journey` '
          'present?',
        );
      }

      final outside = await decide(
        driver,
        placements: [targetLocationPlacement],
        sessionId: freshSession('j2_out'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.addLocationTargeting(
          latitude: londonLatitude,
          longitude: londonLongitude,
        ),
      );
      final outsideCreative = outside.creativeFor(targetLocationPlacement);
      check(outsideCreative == null || !outsideCreative.isJourneyAd(),
          'a coordinate outside the seeded radius excludes the deal');
      if (outsideCreative != null) {
        notes.add('out-of-radius fell through to a competing normal ad, so the '
            'exclusion is attributable to targeting rather than no-fill');
      }
      notes.add('in-radius served stage ${insideCreative.journeyStageKey}');
    });
  });

  scenario(report, 'J3', 'destination targeting: confidence at or above the '
      'threshold serves, below does not', (notes) async {
    await withDriver((driver) async {
      final above = await decide(
        driver,
        placements: [targetDestinationPlacement],
        sessionId: freshSession('j3_above'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.addDestinationTargeting(
          latitude: nycLatitude,
          longitude: nycLongitude,
          minConfidence: destinationThreshold + 0.2,
        ),
      );
      final aboveCreative = above.creativeFor(targetDestinationPlacement);
      if (aboveCreative == null || !aboveCreative.isJourneyAd()) {
        throw SkipScenario(
          'the destination-targeted fixture did not serve above the confidence '
          'threshold on "$targetDestinationPlacement" — is '
          '`e2e_target_destination_journey` present?',
        );
      }

      final below = await decide(
        driver,
        placements: [targetDestinationPlacement],
        sessionId: freshSession('j3_below'),
        opt: JourneyOpt.optIn,
        configure: (builder) => builder.addDestinationTargeting(
          latitude: nycLatitude,
          longitude: nycLongitude,
          minConfidence: destinationThreshold - 0.2,
        ),
      );
      final belowCreative = below.creativeFor(targetDestinationPlacement);
      check(belowCreative == null || !belowCreative.isJourneyAd(),
          'a confidence below the seeded threshold ($destinationThreshold) '
          'excludes the deal');
      notes.add('confidence gate honoured at $destinationThreshold');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §F — runtime-state TTL
//
// The TTL is `journey_definitions.runtime_state_ttl_seconds`, applied verbatim as
// a Redis `SET … EX ttl` with no floor. Advancing to a NEW node re-sets it;
// re-serving the SAME node returns early and does NOT refresh. These two
// scenarios spend real wall-clock time, which is why they run last.
// ────────────────────────────────────────────────────────────────────────────
void ttlGroup() {
  scenario(report, 'F1', 'runtime-state expiry restarts the journey',
      (notes) async {
    await withDriver((driver) async {
      final session = freshSession('f1');
      final first = await decide(
        driver,
        placements: [shortTtlPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final started = first.creativeFor(shortTtlPlacement);
      if (started == null || !started.isJourneyAd()) {
        throw SkipScenario(
          'the short-TTL fixture did not serve on "$shortTtlPlacement" — is '
          '`e2e_short_ttl_journey` present?',
        );
      }
      check(started.isJourneyCompletion != true,
          'the journey did not complete — so a new instance later can only be '
          'the TTL expiring, not a completed journey being replaced');
      final firstInstance = started.journeyInstanceId;

      // Wait past the TTL with a margin. The runtime-state key expires and the
      // same session becomes a brand-new journey.
      await Future.delayed(const Duration(seconds: shortTtlSeconds + 2));

      final afterExpiry = await decide(
        driver,
        placements: [shortTtlPlacement],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final restarted = afterExpiry.creativeFor(shortTtlPlacement);
      check(restarted != null && restarted.isJourneyAd(),
          'the same session serves again after the TTL expired');
      check(restarted!.journeyInstanceId != firstInstance,
          'a NEW instance was minted ($firstInstance → '
          '${restarted.journeyInstanceId}) — the expired state was not resumed');
      notes.add('instance restarted after ${shortTtlSeconds}s TTL expiry');
    });
  });

  scenario(report, 'F2', 'serving a NEW node refreshes the TTL, so the instance '
      'outlives its original deadline', (notes) async {
    await withDriver((driver) async {
      final session = freshSession('f2');
      // The multi-node fixture also carries a 5s TTL, and its three nodes let us
      // advance to a *new* node mid-window — which is the only thing that
      // refreshes the key. Re-serving the same node returns early and does not.
      const step = Duration(milliseconds: 3500);

      final first = await decide(
        driver,
        placements: [multiNodePlacements[0]],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final started = first.creativeFor(multiNodePlacements[0]);
      if (started == null || !started.isJourneyAd()) {
        throw SkipScenario(
          'the multi-node fixture did not serve on "${multiNodePlacements[0]}" '
          '— is `e2e_multinode_journey` present?',
        );
      }
      final instance = started.journeyInstanceId;

      await Future.delayed(step);
      final refreshed = await decide(
        driver,
        placements: [multiNodePlacements[1]],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final refreshedCreative = refreshed.creativeFor(multiNodePlacements[1]);
      check(refreshedCreative != null && refreshedCreative.isJourneyAd(),
          'a new node served mid-window, refreshing the runtime state');
      check(refreshedCreative!.journeyInstanceId == instance,
          'still the same instance');

      // Now past the ORIGINAL 5s deadline, but within the refreshed window.
      await Future.delayed(step);
      final survived = await decide(
        driver,
        placements: [multiNodePlacements[2]],
        sessionId: session,
        opt: JourneyOpt.optIn,
      );
      final survivedCreative = survived.creativeFor(multiNodePlacements[2]);
      check(survivedCreative != null && survivedCreative.isJourneyAd(),
          'the journey still serves past its original creation deadline');
      check(survivedCreative!.journeyInstanceId == instance,
          'the instance survived because the mid-window serve refreshed the TTL '
          '($instance vs ${survivedCreative.journeyInstanceId})');
      notes.add('instance $instance survived '
          '${(step.inMilliseconds * 2) / 1000}s on a ${shortTtlSeconds}s TTL');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// §G — video delivery
//
// A headless runner can prove the SDK EXPOSES the delivery data and does NOT
// auto-fire anything. It cannot drive real playback callbacks — that needs an
// actual player and is flagged as a follow-up rather than faked here.
// ────────────────────────────────────────────────────────────────────────────
void videoGroup() {
  Future<Creative> serveVideo(Driver driver, String placement, String tag) async {
    final served = await decide(
      driver,
      placements: [placement],
      sessionId: freshSession(tag),
      opt: JourneyOpt.optIn,
    );
    final creative = served.creativeFor(placement);
    if (creative == null || !creative.isJourneyAd()) {
      throw SkipScenario(
        'the video fixture did not serve on "$placement" — is its '
        '`e2e_video_*_journey` seeded, and are the VAST env vars set?',
      );
    }
    return creative;
  }

  scenario(report, 'G1', 'a JSON video node exposes json delivery and its video '
      'tracking', (notes) async {
    await withDriver((driver) async {
      final creative = await serveVideo(driver, videoJsonPlacement, 'g1');

      check(creative.delivery == 'json',
          'delivery is "json" (got ${creative.delivery})');
      check(creative.isJsonDelivery(), 'the helper agrees it is JSON delivery');
      check(!creative.isVastTagDelivery() && !creative.isVastXmlDelivery(),
          'and it is not reported as either VAST mode');

      // For JSON delivery the engine owns the beacons, so they must be present
      // for the publisher's player to fire.
      final events = creative.tracking.videoEvents ?? const [];
      check(events.isNotEmpty,
          'video event beacons are exposed for the player to fire '
          '(got ${events.length})');
      for (final event in events) {
        check(isTrackingUrl(event.url),
            'video event "${event.key}" meets the transport contract');
      }

      // Nothing is ever fired automatically.
      driver.client.sent.clear();
      await Future.delayed(const Duration(milliseconds: 300));
      check(driver.client.sent.isEmpty,
          'merely reading the video data fires nothing');
      // Video metadata parity with iOS/Android. Recorded rather than required:
      // whether a given creative is skippable or carries an end card is campaign
      // configuration, but if the engine sends the fields the SDK must surface
      // them rather than drop them.
      final metadata = creative.metadata;
      check(metadata != null, 'the video serve carries a metadata block');
      notes.add('json delivery, ${events.length} video events: '
          '${events.map((e) => e.key).join(", ")}');
      notes.add('metadata: impId=${metadata!.impId} '
          'duration=${metadata.duration} aspect=${metadata.aspectRatio} '
          'skippable=${metadata.isSkippable} '
          'skipOffsetSeconds=${metadata.skipOffsetSeconds} '
          'endCardMode=${metadata.endCardMode}');
    });
  });

  scenario(report, 'G2', 'VAST tag/xml expose the payload and surface NO '
      'VAST-owned beacons', (notes) async {
    await withDriver((driver) async {
      // The double-count rule: for VAST delivery the impression, quartile and
      // click beacons live INSIDE the VAST document and belong to the
      // publisher's player. If the SDK also surfaced them, a publisher wiring up
      // both would count everything twice.
      final tag = await serveVideo(driver, videoVastTagPlacement, 'g2_tag');
      check(tag.delivery == 'vast_tag',
          'delivery is "vast_tag" (got ${tag.delivery})');
      check(tag.isVastTagDelivery(), 'the helper agrees');
      final tagUrl = tag.getVastTagUrl();
      check(tagUrl != null && tagUrl.isNotEmpty,
          'the VAST tag URL is exposed for the player');
      check((tag.tracking.videoEvents ?? const []).isEmpty,
          'NO VAST-owned video-event beacons are surfaced '
          '(got ${tag.tracking.videoEvents?.length ?? 0})');

      final xml = await serveVideo(driver, videoVastXmlPlacement, 'g2_xml');
      check(xml.delivery == 'vast_xml',
          'delivery is "vast_xml" (got ${xml.delivery})');
      check(xml.isVastXmlDelivery(), 'the helper agrees');
      final xmlBase64 = xml.getVastXmlBase64();
      check(xmlBase64 != null && xmlBase64.isNotEmpty,
          'the inline base64 VAST document is exposed');
      check((xml.tracking.videoEvents ?? const []).isEmpty,
          'NO VAST-owned video-event beacons are surfaced for xml either '
          '(got ${xml.tracking.videoEvents?.length ?? 0})');

      driver.client.sent.clear();
      await Future.delayed(const Duration(milliseconds: 300));
      check(driver.client.sent.isEmpty, 'and nothing was auto-fired');
      notes.add('vast_tag + vast_xml exposed with zero SDK-surfaced video '
          'beacons');
    });
  });
}
