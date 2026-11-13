import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/audience_signals.dart';

const MethodChannel _channel = MethodChannel('admoai/device_signals');

/// Coarse native device signals. A field the platform cannot provide is null.
///
/// Native rules (kept in sync with `AdmoaiPlugin.kt` and `AdmoaiPlugin.swift`):
///
/// Android
///  - carrier: only the default-data subscription's network operator name; API
///    >= 24 and a telephony feature are required, otherwise absent.
///  - category: leanback / watch / automotive / pc feature -> `other`;
///    otherwise the smallest full-display width: < 600 dp -> `phone`,
///    >= 600 dp -> `tablet`.
///
/// iOS
///  - carrier: never provided (no CoreTelephony).
///  - category: isiOSAppOnMac / Mac Catalyst -> `other`; idiom phone -> `phone`,
///    pad -> `tablet`, tv / carPlay / mac / vision -> `other`.
class DeviceSignals {
  final String? carrier;
  final DeviceCategory? category;

  const DeviceSignals({this.carrier, this.category});

  static const DeviceSignals empty = DeviceSignals();
}

/// Overrides the host check in tests. Null means use the real platform.
@visibleForTesting
bool? debugMobileHostOverride;

bool _isMobileHost() =>
    debugMobileHostOverride ?? (Platform.isIOS || Platform.isAndroid);

/// Reads coarse native device signals (`carrier`, `category`).
///
/// Never throws. Distinguishes failure from unavailability: returns null when
/// the read failed (timeout, missing plugin, platform error, codec error), so
/// a caller can keep its last snapshot; returns a [DeviceSignals] (possibly with
/// null fields) when the native side answered. On hosts that are neither iOS
/// nor Android ([isMobileHost] false) the channel is not called and the answer
/// is [DeviceSignals.empty]. Non-string or unknown values leave the field absent.
Future<DeviceSignals?> collectDeviceSignals({
  Duration timeout = const Duration(milliseconds: 500),
  bool Function()? isMobileHost,
}) async {
  if (!(isMobileHost ?? _isMobileHost)()) return DeviceSignals.empty;
  try {
    final raw = await _channel
        .invokeMapMethod<String, Object?>('collect')
        .timeout(timeout);
    if (raw == null) return DeviceSignals.empty;
    final carrier = raw['carrier'];
    final category = raw['category'];
    return DeviceSignals(
      carrier: normalizeCarrier(carrier is String ? carrier : null),
      category: DeviceCategory.fromWire(category is String ? category : null),
    );
  } catch (_) {
    // MissingPluginException, PlatformException, TimeoutException, codec errors.
    return null;
  }
}
