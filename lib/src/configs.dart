import 'package:logging/logging.dart';
import 'utils/app_details.dart';
import 'utils/device_details.dart';
import 'utils/device_signals.dart';
import 'utils/device_signals_state.dart';
import 'models/audience_signals.dart';
import 'models/decision_request.dart';

abstract class Clearable {
  factory Clearable.clear() => throw UnimplementedError();
}

class SDKConfig {
  final String baseUrl;
  final String? apiVersion;
  final String? defaultLanguage;
  final Duration requestTimeout;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Logger logger;

  /// Opt-in: when true, the SDK reads the device's mobile carrier and category
  /// (phone, tablet, other) from the platform and sends them as
  /// `device.carrier` / `device.category`. Off by default: a workspace without
  /// audience signals enabled rejects requests that carry these fields, so the
  /// default SDK never sends them. Values set by hand with
  /// [AdMoai.setDeviceConfig] are sent either way.
  final bool collectDeviceSignals;

  SDKConfig({
    required this.baseUrl,
    this.apiVersion,
    this.defaultLanguage,
    this.requestTimeout = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 10),
    Logger? logger,
    this.collectDeviceSignals = false,
  }) : logger = logger ?? Logger('AdMoai');
}

class AppConfig implements Clearable {
  final String? name;
  final String? version;
  final String? buildNumber;
  final String? identifier;
  final String? language;

  AppConfig({
    this.name,
    this.version,
    this.buildNumber,
    this.identifier,
    this.language,
  });

  factory AppConfig.clear() => AppConfig();

  static Future<AppConfig> systemDefault() async {
    final details = await getAppDetails();
    return AppConfig(
      name: details.name,
      version: details.version,
      buildNumber: details.buildNumber,
      identifier: details.identifier,
      language: details.language,
    );
  }
}

class DeviceConfig implements Clearable {
  final String? id;
  final String? model;
  final String? manufacturer;
  final String? os;
  final String? osVersion;
  final String? timezone;
  final String? language;

  /// Mobile carrier name, normalized with [normalizeCarrier]; null when absent.
  final String? carrier;
  final DeviceCategory? category;

  DeviceConfig({
    this.id,
    this.model,
    this.manufacturer,
    this.os,
    this.osVersion,
    this.timezone,
    this.language,
    String? carrier,
    this.category,
  }) : carrier = normalizeCarrier(carrier);

  factory DeviceConfig.clear() => DeviceConfig();

  /// The device as the platform reports it. Carrier and category are read
  /// only when [collectSignals] is true (see [SDKConfig.collectDeviceSignals]);
  /// otherwise the native channel is never called and both stay absent.
  static Future<DeviceConfig> systemDefault(
      {bool collectSignals = false}) async {
    final details = await getDeviceDetails();
    // A failed first read has nothing to fall back to: treat it as empty.
    final signals = collectSignals
        ? await collectDeviceSignals() ?? DeviceSignals.empty
        : DeviceSignals.empty;
    final config = DeviceConfig(
      id: details.id,
      model: details.model,
      manufacturer: details.manufacturer,
      os: details.os,
      osVersion: details.osVersion,
      timezone: details.timezone,
      language: details.language,
      carrier: signals.carrier,
      category: signals.category,
    );
    // Auto signals on (opted in), nothing manual. Kept outside the public API.
    // Without the opt-in the config is not auto, so requests never refresh.
    if (collectSignals) {
      deviceAutoState[config] = const DeviceAutoState(auto: true);
    }
    return config;
  }
}

class UserConfig implements Clearable {
  final String? id;
  final String? ip;
  final String? timezone;
  final Consent consent;

  UserConfig({
    this.id,
    this.ip,
    this.timezone,
    Consent? consent,
  }) : consent = consent ?? Consent();

  factory UserConfig.clear() => UserConfig();
}
