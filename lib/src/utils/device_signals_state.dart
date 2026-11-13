import '../configs.dart';
import '../models/audience_signals.dart';
import 'device_signals.dart';

/// Library-internal bookkeeping for automatic device signals. Not exported
/// from `package:admoai/admoai.dart`: kept off `DeviceConfig`'s public surface
/// so callers cannot depend on it.
///
/// A [DeviceConfig] with no entry (default constructor, `DeviceConfig.clear()`)
/// has auto signals off.
class DeviceAutoState {
  /// Whether native signals are collected for this config.
  final bool auto;

  /// Fields the integrator set by hand; an auto refresh never overwrites them.
  final bool manualCarrier;
  final bool manualCategory;

  const DeviceAutoState({
    this.auto = false,
    this.manualCarrier = false,
    this.manualCategory = false,
  });
}

/// State per [DeviceConfig] instance (configs are immutable).
final Expando<DeviceAutoState> deviceAutoState = Expando<DeviceAutoState>();

DeviceAutoState autoStateOf(DeviceConfig config) =>
    deviceAutoState[config] ?? const DeviceAutoState();

/// Builds the config for `setDeviceConfig`: manual values win and are marked
/// manual per field; the auto flag and earlier manual marks are preserved.
DeviceConfig applyManualDeviceConfig(
  DeviceConfig current, {
  String? id,
  String? model,
  String? manufacturer,
  String? os,
  String? osVersion,
  String? timezone,
  String? language,
  String? carrier,
  DeviceCategory? category,
}) {
  final prev = autoStateOf(current);
  final next = DeviceConfig(
    id: id ?? current.id,
    model: model ?? current.model,
    manufacturer: manufacturer ?? current.manufacturer,
    os: os ?? current.os,
    osVersion: osVersion ?? current.osVersion,
    timezone: timezone ?? current.timezone,
    language: language ?? current.language,
    carrier: carrier ?? current.carrier,
    category: category ?? current.category,
  );
  deviceAutoState[next] = DeviceAutoState(
    auto: prev.auto,
    manualCarrier: prev.manualCarrier || carrier != null,
    manualCategory: prev.manualCategory || category != null,
  );
  return next;
}

/// Re-reads native signals for a config with auto signals on; fields marked
/// manual keep their value.
///
/// Returns [current] unchanged (the same instance) when auto is off, or when
/// the read failed or exceeded [timeout]: the last snapshot is kept. When the
/// native side answered, a null native value means the field is now absent
/// (e.g. the SIM was removed).
Future<DeviceConfig> refreshAutoSignals(
  DeviceConfig current, {
  Duration timeout = const Duration(milliseconds: 500),
}) async {
  final state = autoStateOf(current);
  if (!state.auto) return current;
  final signals = await collectDeviceSignals(timeout: timeout);
  if (signals == null) return current;
  final next = DeviceConfig(
    id: current.id,
    model: current.model,
    manufacturer: current.manufacturer,
    os: current.os,
    osVersion: current.osVersion,
    timezone: current.timezone,
    language: current.language,
    carrier: state.manualCarrier ? current.carrier : signals.carrier,
    category: state.manualCategory ? current.category : signals.category,
  );
  deviceAutoState[next] = state;
  return next;
}
