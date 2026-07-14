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
  }) async {
    return AdMoai._(
      config: config,
      appConfig: await AppConfig.systemDefault(),
      deviceConfig: await DeviceConfig.systemDefault(),
      userConfig: userConfig ?? UserConfig.clear(),
      httpClient: httpClient,
    );
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

  // SDK Operations
  DecisionRequestBuilder createRequestBuilder() {
    return DecisionRequestBuilder(
      appConfig: appConfig,
      deviceConfig: deviceConfig,
      userConfig: userConfig,
    );
  }

  Future<APIResponse<DecisionResponse>> requestAds(
      DecisionRequest request) async {
    return _client.requestDecision(request);
  }

  HTTPRequest getHttpRequest(DecisionRequest request) {
    return _client.getDecisionRequest(request);
  }

  // Tracking
  void fireTracking(String url) {
    if (!Uri.tryParse(url)!.hasScheme) {
      config.logger.warning('Invalid tracking URL: $url');
      return;
    }
    final headers = <String, String>{
      'User-Agent': 'AdMoaiSDK/$sdkVersion',
    };
    if (config.apiVersion != null) {
      headers['X-Tracking-Version'] = config.apiVersion!;
    }
    if (config.defaultLanguage != null) {
      headers['Accept-Language'] = config.defaultLanguage!;
    }
    unawaited(() async {
      try {
        await _httpClient
            .get(Uri.parse(url), headers: headers)
            .timeout(config.requestTimeout);
      } catch (error) {
        config.logger.warning('Tracking request failed: $error');
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

  void fireCustom(Tracking tracking, String key) {
    final url = tracking.getCustomUrl(key: key);
    if (url != null) fireTracking(url);
  }

  void fireVideoEvent(Tracking tracking, String key) {
    final url = tracking.getVideoEventUrl(key: key);
    if (url != null) fireTracking(url);
  }

  void dispose() {
    _httpClient.close();
  }
}
