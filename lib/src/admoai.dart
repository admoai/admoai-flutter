import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import 'configs.dart';
import 'api_client.dart';
import 'models/decision_request.dart';
import 'models/decision_response.dart';
import 'models/decision_request_builder.dart';
import 'version.dart';

class AdMoai {
  final AdMoaiClient _client;
  final SDKConfig config;
  late AppConfig appConfig;
  late DeviceConfig deviceConfig;
  late UserConfig userConfig;
  final http.Client _httpClient;

  /// Sticky, publisher-owned Journey session identifier inherited by every
  /// request builder created via [createRequestBuilder]. Never auto-generated
  /// or auto-rotated by the SDK; the publisher rotates it explicitly via
  /// [setSessionId] (e.g. a new trip). A per-request [DecisionRequestBuilder.setSessionId]
  /// overrides it. Safe for one active Journey per instance; apps running
  /// overlapping journeys should set `sessionId` per request instead.
  String? _sessionId;

  factory AdMoai._({
    required SDKConfig config,
    required AppConfig appConfig,
    required DeviceConfig deviceConfig,
    required UserConfig userConfig,
    http.Client? httpClient,
  }) {
    final resolvedClient = httpClient ?? _defaultHttpClient(config);
    return AdMoai._init(
      config: config,
      appConfig: appConfig,
      deviceConfig: deviceConfig,
      userConfig: userConfig,
      httpClient: resolvedClient,
    );
  }

  AdMoai._init({
    required this.config,
    required this.appConfig,
    required this.deviceConfig,
    required this.userConfig,
    required http.Client httpClient,
  })  : _httpClient = httpClient,
        _client = AdMoaiClient(
          baseUrl: config.baseUrl,
          apiVersion: config.apiVersion,
          defaultLanguage: config.defaultLanguage,
          requestTimeout: config.requestTimeout,
          logger: config.logger,
          httpClient: httpClient,
        );

  static http.Client _defaultHttpClient(SDKConfig config) {
    final ioHttpClient = io.HttpClient()
      ..connectionTimeout = config.connectTimeout
      ..idleTimeout = config.receiveTimeout;
    return http_io.IOClient(ioHttpClient);
  }

  static Future<AdMoai> initialize({
    required SDKConfig config,
    UserConfig? userConfig,
    http.Client? httpClient,
    String? sessionId,
  }) async {
    final sdk = AdMoai._(
      config: config,
      appConfig: await AppConfig.systemDefault(),
      deviceConfig: await DeviceConfig.systemDefault(),
      userConfig: userConfig ?? UserConfig.clear(),
      httpClient: httpClient,
    );
    if (sessionId != null) sdk.setSessionId(sessionId);
    return sdk;
  }

  @visibleForTesting
  static AdMoai forTesting({
    required SDKConfig config,
    AppConfig? appConfig,
    DeviceConfig? deviceConfig,
    UserConfig? userConfig,
    http.Client? httpClient,
  }) {
    return AdMoai._(
      config: config,
      appConfig: appConfig ?? AppConfig.clear(),
      deviceConfig: deviceConfig ?? DeviceConfig.clear(),
      userConfig: userConfig ?? UserConfig.clear(),
      httpClient: httpClient,
    );
  }

  // App Configuration
  void setAppConfig({
    String? name,
    String? version,
    String? buildNumber,
    String? identifier,
    String? language,
  }) {
    appConfig = AppConfig(
      name: name ?? appConfig.name,
      version: version ?? appConfig.version,
      buildNumber: buildNumber ?? appConfig.buildNumber,
      identifier: identifier ?? appConfig.identifier,
      language: language ?? appConfig.language,
    );
  }

  void clearAppConfig() {
    appConfig = AppConfig.clear();
  }

  Future<void> resetAppConfig() async {
    appConfig = await AppConfig.systemDefault();
  }

  // Device Configuration
  void setDeviceConfig({
    String? id,
    String? model,
    String? manufacturer,
    String? os,
    String? osVersion,
    String? timezone,
    String? language,
  }) {
    deviceConfig = DeviceConfig(
      id: id ?? deviceConfig.id,
      model: model ?? deviceConfig.model,
      manufacturer: manufacturer ?? deviceConfig.manufacturer,
      os: os ?? deviceConfig.os,
      osVersion: osVersion ?? deviceConfig.osVersion,
      timezone: timezone ?? deviceConfig.timezone,
      language: language ?? deviceConfig.language,
    );
  }

  void clearDeviceConfig() {
    deviceConfig = DeviceConfig.clear();
  }

  Future<void> resetDeviceConfig() async {
    deviceConfig = await DeviceConfig.systemDefault();
  }

  // User Configuration
  void setUserConfig({
    String? id,
    String? ip,
    String? timezone,
    Consent? consent,
  }) {
    userConfig = UserConfig(
      id: id ?? userConfig.id,
      ip: ip ?? userConfig.ip,
      timezone: timezone ?? userConfig.timezone,
      consent: consent ?? userConfig.consent,
    );
  }

  void clearUserConfig() {
    userConfig = UserConfig.clear();
  }

  // Journey session
  /// Sets the sticky, publisher-owned Journey [sessionId] inherited by future
  /// request builders. Rotate it when the publisher's own rules decide a new
  /// journey begins (e.g. device locked 2h+). Emits a PII-safe warning (reason
  /// token only, never the value) when the engine would treat it as absent.
  void setSessionId(String sessionId) {
    final reason = journeySessionIdRejectionReason(sessionId);
    if (reason != null) {
      config.logger.warning(
        'sessionId will disable Journey (reason: $reason)',
      );
    }
    // Normalize so the stored value matches what is serialized: trim, and
    // treat blank-after-trim as "no session" (null). Over-length values are
    // kept as-is (the engine is authoritative and rejects them server-side).
    final trimmed = sessionId.trim();
    _sessionId = trimmed.isEmpty ? null : trimmed;
  }

  void clearSessionId() {
    _sessionId = null;
  }

  // SDK Operations
  DecisionRequestBuilder createRequestBuilder() {
    return DecisionRequestBuilder(
      appConfig: appConfig,
      deviceConfig: deviceConfig,
      userConfig: userConfig,
      sessionId: _sessionId,
      logger: config.logger,
    );
  }

  Future<APIResponse<DecisionResponse>> requestAds(
      DecisionRequest request) async {
    _warnIfJourneyWithoutApiVersion(request);
    return _client.requestDecision(request);
  }

  HTTPRequest getHttpRequest(DecisionRequest request) {
    _warnIfJourneyWithoutApiVersion(request);
    return _client.getDecisionRequest(request);
  }

  /// The decision endpoint version-routes on `X-Decision-Version`; Journey fields
  /// only reach the Journey-capable handler on `2025-11-01` or later. Without an
  /// [SDKConfig.apiVersion] the engine **silently** ignores `sessionId` /
  /// `journeyOpt` and serves normal ads — no error, no empty response, nothing to
  /// notice. Warn so the misconfiguration is visible during integration rather
  /// than read as "no Journey was eligible".
  void _warnIfJourneyWithoutApiVersion(DecisionRequest request) {
    if (config.apiVersion != null) return;
    // Mirror the wire: a blank-after-trim sessionId is never sent, so it is not
    // Journey context and must not trigger the warning.
    final hasSession = (request.sessionId?.trim().isNotEmpty ?? false);
    if (!hasSession && request.journeyOpt == null) return;
    config.logger.warning(
      'Journey context set but apiVersion is null; Journey will be ignored.',
    );
  }

  // Tracking
  void fireTracking(String url) {
    final uri = Uri.tryParse(url);
    // Require an absolute http(s) URL with a host. `hasScheme` alone would admit
    // `mailto:`, `file:`, `ftp://…` and scheme-only strings, which cannot be a
    // beacon the engine minted. PII-safe: the URL carries an opaque `?e=` token,
    // so log a redacted reason and never the value.
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      config.logger.warning(
        'Tracking URL rejected: not an absolute http(s) URL',
      );
      return;
    }
    final headers = <String, String>{
      'User-Agent': 'AdMoaiSDK/$sdkVersion',
    };
    // The tracking endpoint (/v1/tracking) version-routes on X-Tracking-Version
    // and ignores X-Decision-Version. Journey enrichment + custom-event
    // completion only run on the versioned tracking handler, so the SDK must
    // send X-Tracking-Version (using the configured apiVersion). When unset,
    // no version header is sent and the engine defaults gracefully.
    if (config.apiVersion != null) {
      headers['X-Tracking-Version'] = config.apiVersion!;
    }
    if (config.defaultLanguage != null) {
      headers['Accept-Language'] = config.defaultLanguage!;
    }
    unawaited(() async {
      try {
        await _httpClient
            .get(uri, headers: headers)
            .timeout(config.requestTimeout);
      } catch (error) {
        // PII-safe: log the error TYPE only, never the object. `http`'s ClientException
        // stringifies as "ClientException: <message>, uri=<uri>", so interpolating `$error`
        // wrote the full tracking URL — including the opaque `?e=` token that encodes the
        // serve-time context — into the publisher's logs. That contradicted the redacted-reason
        // guard a few lines above, and it fired routinely rather than rarely: any connection
        // refusal or TLS failure takes this path.
        config.logger.warning(
          'Tracking request failed (${error.runtimeType}); URL withheld',
        );
      }
    }());
  }

  void fireImpression(Tracking tracking, {String key = 'default'}) {
    final url = tracking.getImpressionUrl(key: key);
    if (url != null) fireTracking(url);
  }

  void fireClick(Tracking tracking, {String key = 'default'}) {
    final url = tracking.getClickUrl(key: key);
    if (url != null) fireTracking(url);
  }

  /// Fires the custom-event beacon for [key]. Named to match the Android SDK's
  /// `fireCustomEvent`.
  void fireCustomEvent(Tracking tracking, String key) {
    final url = tracking.getCustomUrl(key: key);
    if (url != null) fireTracking(url);
  }

  /// Deprecated alias for [fireCustomEvent], kept so existing integrations keep
  /// compiling. iOS still exposes `fireCustom`; all three SDKs are converging on
  /// `fireCustomEvent`.
  @Deprecated('Renamed to fireCustomEvent for cross-SDK parity. '
      'Will be removed in 1.0.0.')
  void fireCustom(Tracking tracking, String key) =>
      fireCustomEvent(tracking, key);

  void fireVideoEvent(Tracking tracking, String key) {
    final url = tracking.getVideoEventUrl(key: key);
    if (url != null) fireTracking(url);
  }

  /// Fires the server-provided Journey completion URL for [key]. Only relevant
  /// for `custom_event` completion deals, where `tracking.completions` is
  /// populated; fire it once when the publisher-mapped completion action
  /// occurs. `final_stage` deals carry no completion URL (completion is
  /// recorded server-side) — do not synthesize one. The SDK never infers or
  /// emits completion locally.
  void fireCompletion(Tracking tracking, {required String key}) {
    final url = tracking.getCompletionUrl(key: key);
    if (url != null) {
      if (config.apiVersion == null) {
        // Billing-critical: /v1/tracking version-routes on X-Tracking-Version,
        // which is derived from apiVersion. With none, the callback lands on the
        // legacy handler, which does not record the completion — so CPT revenue
        // is silently lost while the fire itself looks successful.
        config.logger.warning(
          'Firing Journey completion without apiVersion; it may not record.',
        );
      }
      fireTracking(url);
    } else if (tracking.completions?.isNotEmpty ?? false) {
      // Completion URLs exist but none matches `key` — a likely publisher
      // mistake. Completion is billing-critical, so surface it rather than
      // silently firing nothing (unlike final_stage, which has no completions).
      config.logger.warning(
        'fireCompletion: no completion URL for key "$key" — nothing fired',
      );
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
