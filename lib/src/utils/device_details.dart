import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

bool isTesting = false;

class DeviceDetails {
  final String? id;
  final String? model;
  final String? manufacturer;
  final String? os;
  final String? osVersion;
  final String? timezone;
  final String? language;

  DeviceDetails({
    this.id,
    this.model,
    this.manufacturer,
    this.os,
    this.osVersion,
    this.timezone,
    this.language,
  });
}

Future<DeviceDetails> getDeviceDetails() async {
  final deviceInfo = DeviceInfoPlugin();
  final locale = WidgetsBinding.instance.window.locale;

  if (Platform.isIOS) {
    final iosInfo = await deviceInfo.iosInfo;
    return DeviceDetails(
      id: iosInfo.identifierForVendor,
      model: iosInfo.model,
      manufacturer: 'Apple',
      os: 'iOS',
      osVersion: iosInfo.systemVersion,
      timezone: DateTime.now().timeZoneName,
      language: locale.languageCode,
    );
  } else if (Platform.isAndroid) {
    final androidInfo = await deviceInfo.androidInfo;
    return DeviceDetails(
      id: androidInfo.id,
      model: androidInfo.model,
      manufacturer: androidInfo.manufacturer,
      os: 'Android',
      osVersion: androidInfo.version.release,
      timezone: DateTime.now().timeZoneName,
      language: locale.languageCode,
    );
  }

  return DeviceDetails();
}
