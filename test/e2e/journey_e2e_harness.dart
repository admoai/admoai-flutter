// ignore_for_file: avoid_print
//
// Harness for the Journey Ads live E2E runner.
//
// Black-box by design: every assertion is made against what a customer's app can
// observe — the SDK result and the `/decision` transport. Engine internals (Redis
// runtime state, decoded tracking-token identity, billing dedupe and totals,
// reporting, concurrency) are out of scope and owned by adhub's Go service-layer
// tests. Asserting them from an SDK is impossible; pretending otherwise produces
// false confidence.
//
// The design decisions here were earned on the Android runner; each exists
// because the naive alternative produced a wrong or useless result. See
// test/e2e/README.md.

import 'dart:convert';
import 'dart:io';

import 'package:admoai/admoai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:logging/logging.dart';

/// Base URL of the locally-running decision-engine. No trailing slash.
final String e2eBaseUrl = (Platform.environment['ADMOAI_JOURNEY_E2E_BASE_URL'] ??
        'http://127.0.0.1:8080')
    .replaceAll(RegExp(r'/+$'), '');

/// The Journey-capable API version. A wrong version is a hard gate: the engine
/// silently ignores journey fields and serves normal ads.
final String e2eApiVersion =
    Platform.environment['ADMOAI_JOURNEY_E2E_VERSION'] ?? '2025-11-01';

const String reportPath = 'build/journey-e2e/report.json';

enum Outcome { pass, fail, skip }

class ScenarioResult {
  ScenarioResult({
    required this.id,
    required this.title,
    required this.outcome,
    this.detail,
    this.notes = const [],
  });

  final String id;
  final String title;
  final Outcome outcome;

  /// Failure message, or the reason a scenario was skipped.
  final String? detail;

  /// Observations recorded while the scenario ran. Kept in the report so a later
  /// round can diff what the engine actually returned, not just pass/fail.
  final List<String> notes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'outcome': outcome.name.toUpperCase(),
        if (detail != null) 'detail': detail,
        if (notes.isNotEmpty) 'notes': notes,
      };
}

/// Thrown by a scenario body when the fixture it needs was never seeded.
///
/// A missing fixture is an environment fact, not a defect, so it must SKIP rather
/// than FAIL — otherwise a `db-reset` reads as a regression.
class SkipScenario implements Exception {
  SkipScenario(this.reason);
  final String reason;
  @override
  String toString() => 'SkipScenario: $reason';
}

/// Aborts the whole run: the environment is unusable, so every scenario would
/// fail for the same reason. Reported once, with a diagnosis, as exit 2.
class PreflightAbort implements Exception {
  PreflightAbort(this.diagnosis, {this.recipe});
  final String diagnosis;
  final String? recipe;
  @override
  String toString() => 'PreflightAbort: $diagnosis';
}

/// Records scenario outcomes and writes the machine-readable report.
class E2eReport {
  final List<ScenarioResult> results = [];
  String? preflightDiagnosis;
  String? preflightRecipe;

  int get passed => results.where((r) => r.outcome == Outcome.pass).length;
  int get failed => results.where((r) => r.outcome == Outcome.fail).length;
  int get skipped => results.where((r) => r.outcome == Outcome.skip).length;

  void add(ScenarioResult result) {
    results.add(result);
    final label = result.outcome.name.toUpperCase().padRight(4);
    print('$label ${result.id.padRight(7)} ${result.title}');
    for (final note in result.notes) {
      print('          · $note');
    }
    if (result.detail != null) {
      print('          → ${result.detail}');
    }
  }

  /// Exit code contract, matching the Android runner:
  /// 0 = pass (a documented SKIP is allowed), 1 = a scenario FAILED,
  /// 2 = preflight aborted / environment unusable.
  int get exitCode {
    if (preflightDiagnosis != null) return 2;
    return failed > 0 ? 1 : 0;
  }

  void write() {
    final file = File(reportPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'baseUrl': e2eBaseUrl,
      'apiVersion': e2eApiVersion,
      if (preflightDiagnosis != null)
        'preflight': {
          'aborted': true,
          'diagnosis': preflightDiagnosis,
          if (preflightRecipe != null) 'recipe': preflightRecipe,
        }
      else
        'preflight': {'aborted': false},
      'summary': {
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'total': results.length,
      },
      'exitCode': exitCode,
      'scenarios': results.map((r) => r.toJson()).toList(),
    }));
  }

  void printSummary() {
    print('');
    if (preflightDiagnosis != null) {
      print('PREFLIGHT ABORTED — the environment is unusable, not the SDK.');
      print('  $preflightDiagnosis');
      if (preflightRecipe != null) print('  fix: $preflightRecipe');
    }
    print('Journey E2E: $passed passed, $failed failed, $skipped skipped '
        '(${results.length} total)');
    print('Report: $reportPath   (exit $exitCode)');
    if (skipped > 0) {
      print('');
      print('SKIPPED scenarios are NOT failures, but they are also NOT '
          'coverage. Before signing off, confirm every SKIP is deliberate:');
      for (final r in results.where((r) => r.outcome == Outcome.skip)) {
        print('  ${r.id}: ${r.detail}');
      }
    }
  }
}

/// Records every outbound request URL while forwarding to the real network.
///
/// Lets a scenario assert that a tracking URL was fired **byte-identical** while
/// still exercising real HTTP, which a mock-only check cannot do.
class RecordingClient extends http.BaseClient {
  RecordingClient(this._inner);

  final http.Client _inner;
  final List<String> sent = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent.add(request.url.toString());
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// One SDK instance plus the record of what it put on the wire.
class Driver {
  Driver(this.sdk, this.client, this.logs);

  final AdMoai sdk;
  final RecordingClient client;
  final List<LogRecord> logs;

  void dispose() => sdk.dispose();
}

int _sessionCounter = 0;

/// A session id unique to this scenario **and this run**.
///
/// Uniqueness per run is what makes the suite re-runnable with no reseed and no
/// Redis flush: journey runtime-state keys and `fc_journey:` cap keys can never
/// collide across runs. Without it the suite is a one-shot.
String freshSession(String tag) =>
    'e2e_${tag}_${DateTime.now().microsecondsSinceEpoch}_${_sessionCounter++}';

/// A user id unique to this scenario and run — required for the frequency-cap
/// scenarios, whose Redis sorted-set keys are per user + deal.
String freshUser(String tag) =>
    'e2e_user_${tag}_${DateTime.now().microsecondsSinceEpoch}_${_sessionCounter++}';

/// Installs the platform-channel stubs the SDK's system-default config needs, so
/// the runner can drive the **real** `AdMoai.initialize` rather than a test seam,
/// and re-enables real networking.
///
/// **The networking part is not optional.** `TestWidgetsFlutterBinding` installs
/// an `HttpOverrides` that intercepts every `HttpClient` and answers **HTTP 400
/// with an empty body** without touching the network. A suite that needs a live
/// engine and does not clear it is not testing the engine at all — it is asserting
/// against Flutter's mock. `test/integration_live_test.dart` shipped in exactly
/// that state: every "live" call returned 400 and the suite soft-logged it as a
/// warning, so it stayed green while covering nothing.
///
/// Must be called after the binding is initialized, because the binding is what
/// installs the override.
void installPlatformChannelStubs() {
  HttpOverrides.global = null;

  const timezone = MethodChannel('flutter_timezone');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(timezone, (call) async {
    if (call.method == 'getLocalTimezone') return 'UTC';
    return null;
  });
}

/// Fails loudly if the test binding's HTTP override is still installed.
///
/// Cheap insurance against the failure mode above coming back: it would turn every
/// scenario into an identical, meaningless 400.
void assertRealNetworkingEnabled() {
  if (HttpOverrides.current != null) {
    throw PreflightAbort(
      'the Flutter test binding\'s HttpOverrides is still installed, so every '
      'request would return a mocked HTTP 400 without reaching the engine',
      recipe: 'call installPlatformChannelStubs() (which clears '
          'HttpOverrides.global) after TestWidgetsFlutterBinding.ensureInitialized()',
    );
  }
}

/// Builds a driver over the real public entry point.
///
/// [apiVersion] is passed through so a scenario can prove the version gate by
/// omitting it.
Future<Driver> newDriver({
  String? apiVersion = _defaultVersion,
  String? sessionId,
}) async {
  final logs = <LogRecord>[];
  final logger = Logger('e2e-${_sessionCounter++}')
    ..level = Level.ALL
    ..onRecord.listen(logs.add);
  final client = RecordingClient(http_io.IOClient(HttpClient()));

  final sdk = await AdMoai.initialize(
    config: SDKConfig(
      baseUrl: e2eBaseUrl,
      apiVersion: apiVersion == _defaultVersion ? e2eApiVersion : apiVersion,
      logger: logger,
      requestTimeout: const Duration(seconds: 20),
    ),
    httpClient: client,
    sessionId: sessionId,
  );
  return Driver(sdk, client, logs);
}

const String _defaultVersion = '__default__';

/// Runs [body] with a driver and always disposes it.
Future<T> withDriver<T>(
  Future<T> Function(Driver d) body, {
  String? apiVersion = _defaultVersion,
  String? sessionId,
}) async {
  final driver = await newDriver(apiVersion: apiVersion, sessionId: sessionId);
  try {
    return await body(driver);
  } finally {
    driver.dispose();
  }
}

/// The observable result of one `/decision` call.
class Served {
  Served(this.decisions, this.statusCode, this.rawBody);

  final List<Decision> decisions;
  final int statusCode;
  final String? rawBody;

  Decision? decisionFor(String placement) =>
      decisions.where((d) => d.placement == placement).firstOrNull;

  /// The first creative on [placement], or null on a no-ad.
  Creative? creativeFor(String placement) {
    final decision = decisionFor(placement);
    if (decision == null || decision.isNoAd) return null;
    return decision.creatives!.first;
  }

  bool isNoAdFor(String placement) {
    final decision = decisionFor(placement);
    return decision == null || decision.isNoAd;
  }
}

/// Issues a decision request through the SDK.
///
/// [configure] receives the builder so a scenario can add user id or targeting.
/// The parameter is deliberately **not** named anything that could collide with a
/// builder method: on Android an identically-motivated helper took a lambda named
/// `build`, which bound to the builder's own `build()` inside the receiver scope
/// and silently dropped every caller's `setUserId`/targeting. Requests went out
/// with no user and no targeting, so the frequency cap never applied and targeted
/// deals were excluded — and it looked exactly like an engine bug. Dart has no
/// receiver-lambda scope to shadow, and `e2eSelfCheck` proves the forwarding.
Future<Served> decide(
  Driver driver, {
  required List<String> placements,
  String? sessionId,
  JourneyOpt? opt,
  void Function(DecisionRequestBuilder builder)? configure,
}) async {
  final builder = driver.sdk.createRequestBuilder();
  for (final placement in placements) {
    builder.addPlacement(key: placement);
  }
  if (sessionId != null) builder.setSessionId(sessionId);
  if (opt != null) builder.setJourneyOpt(opt);
  configure?.call(builder);

  final response = await driver.sdk.requestAds(builder.build());
  return Served(
    response.body.data ?? const [],
    response.response.statusCode,
    response.rawBody,
  );
}

/// Rewrites an engine-minted tracking URL onto the configured base URL.
///
/// The local engine mints production-shaped `https://` URLs while serving
/// plaintext on `:8080`, so firing one verbatim fails the TLS handshake locally.
/// That is an environment artifact, not a defect. Scheme, host and port are
/// normalized; the opaque `?e=` token is left untouched — rewriting it would
/// invalidate the very thing under test.
String normalizeForLocalIngestion(String url) {
  final minted = Uri.parse(url);
  final target = Uri.parse(e2eBaseUrl);
  return minted
      .replace(scheme: target.scheme, host: target.host, port: target.port)
      .toString();
}

/// True when [url] meets the tracking transport contract: absolute, path
/// `/v1/tracking`, carrying an opaque `?e=` token.
bool isTrackingUrl(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isAbsolute) return false;
  if (!uri.path.startsWith('/v1/tracking')) return false;
  final token = uri.queryParameters['e'];
  return token != null && token.isNotEmpty;
}

/// Registers a scenario as a `test()` so `flutter test` output stays readable,
/// while recording the real PASS/FAIL/SKIP outcome into [report].
///
/// A scenario that throws [SkipScenario] is recorded SKIP and does not fail the
/// run; any other error is a FAIL carrying the message.
void scenario(
  E2eReport report,
  String id,
  String title,
  Future<void> Function(List<String> notes) body,
) {
  test('$id — $title', () async {
    if (report.preflightDiagnosis != null) {
      report.add(ScenarioResult(
        id: id,
        title: title,
        outcome: Outcome.skip,
        detail: 'preflight aborted: ${report.preflightDiagnosis}',
      ));
      return;
    }
    final notes = <String>[];
    try {
      await body(notes);
      report.add(ScenarioResult(
        id: id,
        title: title,
        outcome: Outcome.pass,
        notes: notes,
      ));
    } on SkipScenario catch (skip) {
      report.add(ScenarioResult(
        id: id,
        title: title,
        outcome: Outcome.skip,
        detail: skip.reason,
        notes: notes,
      ));
    } catch (error, stack) {
      report.add(ScenarioResult(
        id: id,
        title: title,
        outcome: Outcome.fail,
        detail: _firstLines(error, stack),
        notes: notes,
      ));
    }
  });
}

String _firstLines(Object error, StackTrace stack) {
  final message = error.toString().split('\n').take(6).join(' | ');
  final frame = stack
      .toString()
      .split('\n')
      .firstWhere((l) => l.contains('journey_e2e'), orElse: () => '');
  return frame.isEmpty ? message : '$message  [$frame.trim()]';
}

/// Assertion helper that reads as a claim in the report rather than a matcher.
void check(bool condition, String claim) {
  if (!condition) throw StateError('expected: $claim');
}
