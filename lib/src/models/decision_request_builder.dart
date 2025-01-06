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

  DecisionRequestBuilder({
    required AppConfig appConfig,
    required DeviceConfig deviceConfig,
    required UserConfig userConfig,
  }) {
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
    int count = 1,
    Format format = Format.native,
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
    if (_targeting == null) {
      _targeting = Targeting(geo: geoNameIds);
    } else {
      _targeting = Targeting(
        geo: geoNameIds,
        location: _targeting?.location,
        custom: _targeting?.custom,
      );
    }
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

    if (_targeting == null) {
      _targeting = Targeting(location: uniqueLocations);
    } else {
      _targeting = Targeting(
        geo: _targeting?.geo,
        location: uniqueLocations,
        custom: _targeting?.custom,
      );
    }
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

    if (_targeting == null) {
      _targeting = Targeting(custom: uniqueCustom);
    } else {
      _targeting = Targeting(
        geo: _targeting?.geo,
        location: _targeting?.location,
        custom: uniqueCustom,
      );
    }
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

  DecisionRequestBuilder clearAll() {
    clearPlacements();
    clearTargeting();
    clearUser();
    disableDeviceCollection();
    disableAppCollection();
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
    );
  }
}
