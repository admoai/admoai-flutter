import 'package:logging/logging.dart';
import 'utils/app_details.dart';
import 'utils/device_details.dart';
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

  SDKConfig({
    required this.baseUrl,
    this.apiVersion,
    this.defaultLanguage,
    this.requestTimeout = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 10),
    Logger? logger,
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

  DeviceConfig({
    this.id,
    this.model,
    this.manufacturer,
    this.os,
    this.osVersion,
    this.timezone,
    this.language,
  });

  factory DeviceConfig.clear() => DeviceConfig();

  static Future<DeviceConfig> systemDefault() async {
    final details = await getDeviceDetails();
    return DeviceConfig(
      id: details.id,
      model: details.model,
      manufacturer: details.manufacturer,
      os: details.os,
      osVersion: details.osVersion,
      timezone: details.timezone,
      language: details.language,
    );
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
