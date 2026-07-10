import 'package:logging/logging.dart';

import 'decision_request.dart';
import '../configs.dart';

class DecisionRequestBuilder {
  final List<Placement> _placements = [];
  Targeting? _targeting;
  User? _user;
  Device? _device;
  App? _app;
  bool _collectAppData = true;
  bool _collectDeviceData = true;
  String? _sessionId;
  JourneyOpt? _journeyOpt;
  final Logger _logger;

  DecisionRequestBuilder({
    required AppConfig appConfig,
    required DeviceConfig deviceConfig,
    required UserConfig userConfig,
    String? sessionId,
    Logger? logger,
  }) : _sessionId = sessionId,
        _logger = logger ?? Logger('AdMoai') {
    _app = App(
      name: appConfig.name,
      version: appConfig.version,
      buildNumber: appConfig.buildNumber,
      identifier: appConfig.identifier,
      language: appConfig.language,
    );

    _device = Device(
      id: deviceConfig.id,
      model: deviceConfig.model,
      manufacturer: deviceConfig.manufacturer,
      os: deviceConfig.os,
      osVersion: deviceConfig.osVersion,
      timezone: deviceConfig.timezone,
      language: deviceConfig.language,
    );

    _user = User(
      id: userConfig.id,
      ip: userConfig.ip,
      timezone: userConfig.timezone,
      consent: userConfig.consent,
    );
  }

  // Placement methods
  DecisionRequestBuilder addPlacement({
    required String key,
    int? count,
    Format? format,
    String? advertiserId,
    String? templateId,
  }) {
    _placements.add(Placement(
      key: key,
      count: count,
      format: format,
      advertiserId: advertiserId,
      templateId: templateId,
    ));
    return this;
  }

  // Targeting methods
  DecisionRequestBuilder setGeoTargeting(List<int>? geoNameIds) {
    _targeting = Targeting(
      geo: geoNameIds,
      location: _targeting?.location,
      destination: _targeting?.destination,
      custom: _targeting?.custom,
    );
    return this;
  }

  DecisionRequestBuilder addGeoTargeting(int geoNameId) {
    final currentGeo = List<int>.from(_targeting?.geo ?? []);
    currentGeo.add(geoNameId);
    return setGeoTargeting(currentGeo);
  }

  DecisionRequestBuilder clearGeoTargeting() {
    if (_targeting != null) {
      _targeting = Targeting(
        geo: null,
        location: _targeting?.location,
        destination: _targeting?.destination,
        custom: _targeting?.custom,
      );
    }
    return this;
  }

  DecisionRequestBuilder setLocationTargeting(List<Location> locations) {
    final uniqueLocations = locations.fold<List<Location>>(
      [],
      (result, coordinate) {
        final exists = result.any((existing) =>
            existing.latitude == coordinate.latitude &&
            existing.longitude == coordinate.longitude);
        if (!exists) {
          result.add(coordinate);
        }
        return result;
      },
    );

    _targeting = Targeting(
      geo: _targeting?.geo,
      location: uniqueLocations,
      destination: _targeting?.destination,
      custom: _targeting?.custom,
    );
    return this;
  }

  DecisionRequestBuilder addLocationTargeting({
    required double latitude,
    required double longitude,
  }) {
    final currentLocations = List<Location>.from(_targeting?.location ?? []);
    currentLocations.add(Location(latitude: latitude, longitude: longitude));
    return setLocationTargeting(currentLocations);
  }

  DecisionRequestBuilder clearLocationTargeting() {
    if (_targeting != null) {
      _targeting = Targeting(
        geo: _targeting?.geo,
        location: null,
        destination: _targeting?.destination,
        custom: _targeting?.custom,
      );
    }
    return this;
  }

  DecisionRequestBuilder setDestinationTargeting(
      List<Destination>? destinations) {
    final unique = destinations?.fold<List<Destination>>(
      [],
      (result, dest) {
        final exists = result.any((existing) =>
            existing.latitude == dest.latitude &&
            existing.longitude == dest.longitude &&
            existing.minConfidence == dest.minConfidence);
        if (!exists) {
          result.add(dest);
        }
        return result;
      },
    );

    _targeting = Targeting(
      geo: _targeting?.geo,
      location: _targeting?.location,
      destination: unique,
      custom: _targeting?.custom,
    );
    return this;
  }

  DecisionRequestBuilder addDestinationTargeting({
    required double latitude,
    required double longitude,
    required double minConfidence,
  }) {
    if (minConfidence < 0.0 || minConfidence > 1.0) {
      throw ArgumentError.value(
        minConfidence,
        'minConfidence',
        'must be between 0.0 and 1.0 inclusive',
      );
    }
    final current = List<Destination>.from(_targeting?.destination ?? []);
    current.add(Destination(
      latitude: latitude,
      longitude: longitude,
      minConfidence: minConfidence,
    ));
    return setDestinationTargeting(current);
  }

  DecisionRequestBuilder clearDestinationTargeting() {
    if (_targeting != null) {
      _targeting = Targeting(
        geo: _targeting?.geo,
        location: _targeting?.location,
        destination: null,
        custom: _targeting?.custom,
      );
    }
    return this;
  }

  DecisionRequestBuilder setCustomTargeting(List<CustomKeyValue>? custom) {
    final uniqueCustom = custom?.fold<List<CustomKeyValue>>(
      [],
      (result, keyValue) {
        result.removeWhere((item) => item.key == keyValue.key);
        result.add(keyValue);
        return result;
      },
    );

    _targeting = Targeting(
      geo: _targeting?.geo,
      location: _targeting?.location,
      destination: _targeting?.destination,
      custom: uniqueCustom,
    );
    return this;
  }

  DecisionRequestBuilder addCustomTargeting({
    required String key,
    required dynamic value,
  }) {
    final currentCustom = List<CustomKeyValue>.from(_targeting?.custom ?? []);
    currentCustom.add(CustomKeyValue(key: key, value: value));
    return setCustomTargeting(currentCustom);
  }

  DecisionRequestBuilder clearCustomTargeting() {
    if (_targeting != null) {
      _targeting = Targeting(
        geo: _targeting?.geo,
        location: _targeting?.location,
        destination: _targeting?.destination,
        custom: null,
      );
    }
    return this;
  }

  // User methods
  DecisionRequestBuilder setUserId(String? id) {
    if (_user == null) {
      _user = User(id: id);
    } else {
      _user = User(
        id: id,
        ip: _user?.ip,
        timezone: _user?.timezone,
        consent: _user?.consent,
      );
    }
    return this;
  }

  DecisionRequestBuilder setUserIp(String? ip) {
    if (_user == null) {
      _user = User(ip: ip);
    } else {
      _user = User(
        id: _user?.id,
        ip: ip,
        timezone: _user?.timezone,
        consent: _user?.consent,
      );
    }
    return this;
  }

  DecisionRequestBuilder setUserTimezone(String? timezone) {
    if (_user == null) {
      _user = User(timezone: timezone);
    } else {
      _user = User(
        id: _user?.id,
        ip: _user?.ip,
        timezone: timezone,
        consent: _user?.consent,
      );
    }
    return this;
  }

  DecisionRequestBuilder setUserConsent(Consent? consent) {
    if (_user == null) {
      _user = User(consent: consent);
    } else {
      _user = User(
        id: _user?.id,
        ip: _user?.ip,
        timezone: _user?.timezone,
        consent: consent,
      );
    }
    return this;
  }

  // Journey methods
  /// Sets the per-request Journey session identifier, overriding any sticky
  /// SDK-level default seeded into this builder. Emits a PII-safe warning
  /// (reason token only, never the value) when the engine would treat the
  /// value as absent (blank-after-trim or > 256 UTF-8 bytes).
  DecisionRequestBuilder setSessionId(String sessionId) {
    final reason = journeySessionIdRejectionReason(sessionId);
    if (reason != null) {
      _logger.warning(
        'sessionId will disable Journey for this request (reason: $reason)',
      );
    }
    // Normalize so the built request's `sessionId` matches the wire: trim, and
    // treat blank-after-trim as null. Over-length kept as-is (engine rejects).
    final trimmed = sessionId.trim();
    _sessionId = trimmed.isEmpty ? null : trimmed;
    return this;
  }

  DecisionRequestBuilder clearSessionId() {
    _sessionId = null;
    return this;
  }

  /// Forwards the publisher-provided Journey opt control without interpreting
  /// progression locally.
  DecisionRequestBuilder setJourneyOpt(JourneyOpt opt) {
    _journeyOpt = opt;
    return this;
  }

  DecisionRequestBuilder clearJourneyOpt() {
    _journeyOpt = null;
    return this;
  }

  // Collection control methods
  DecisionRequestBuilder disableAppCollection() {
    _collectAppData = false;
    _app = null;
    return this;
  }

  DecisionRequestBuilder disableDeviceCollection() {
    _collectDeviceData = false;
    _device = null;
    return this;
  }

  // Clear methods
  DecisionRequestBuilder clearPlacements() {
    _placements.clear();
    return this;
  }

  DecisionRequestBuilder clearTargeting() {
    _targeting = null;
    return this;
  }

  DecisionRequestBuilder clearUser() {
    _user = null;
    return this;
  }

  /// Resets the builder for reuse. Clears placements, targeting, user, and
  /// disables app/device collection. Also clears the per-request Journey
  /// override [_journeyOpt] — it is a per-decision control and must not leak
  /// (e.g. a stale `optOut`) into an unrelated reused request.
  ///
  /// The sticky Journey [_sessionId] is intentionally **preserved**: it is a
  /// session-scoped default (seeded from [AdMoai] / set explicitly) and is
  /// meant to persist across requests in the same journey. Call
  /// [clearSessionId] to drop it explicitly.
  DecisionRequestBuilder clearAll() {
    clearPlacements();
    clearTargeting();
    clearUser();
    disableDeviceCollection();
    disableAppCollection();
    clearJourneyOpt();
    return this;
  }

  // Build method
  DecisionRequest build() {
    return DecisionRequest(
      placements: _placements,
      targeting: _targeting,
      user: _user,
      device: _collectDeviceData ? _device : null,
      app: _collectAppData ? _app : null,
      sessionId: _sessionId,
      journeyOpt: _journeyOpt,
    );
  }
}
