import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppDetails {
  final String? name;
  final String? version;
  final String? buildNumber;
  final String? identifier;
  final String? language;

  AppDetails({
    this.name,
    this.version,
    this.buildNumber,
    this.identifier,
    this.language,
  });
}

bool isTesting = false;

Future<AppDetails> getAppDetails() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final locale = WidgetsBinding.instance.window.locale;

    return AppDetails(
      name: packageInfo.appName,
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      identifier: packageInfo.packageName,
      language: locale.languageCode,
    );
  } catch (e) {
    return AppDetails();
  }
}
