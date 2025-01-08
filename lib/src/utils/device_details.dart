import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:io';

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
  final timezone = await FlutterTimezone.getLocalTimezone();

  if (Platform.isIOS) {
    final iosInfo = await deviceInfo.iosInfo;
    return DeviceDetails(
      id: iosInfo.identifierForVendor,
      model: iosInfo.utsname.machine,
      manufacturer: 'Apple',
      os: 'iOS',
      osVersion: iosInfo.systemVersion,
      timezone: timezone,
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
      timezone: timezone,
      language: locale.languageCode,
    );
  }

  return DeviceDetails();
}
