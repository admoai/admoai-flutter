import 'dart:convert';

/// Explicit runtime opt control for Journey Takeover Ads.
///
/// The decision-engine accepts only the wire literals `"in"` / `"out"`;
/// any other value is rejected with HTTP 400. `in`/`out` are Dart keywords,
/// so the enum members are named [optIn] / [optOut] and expose the wire
/// string via [value].
enum JourneyOpt {
  optIn('in'),
  optOut('out');

  final String value;
  const JourneyOpt(this.value);

  /// Tolerant Reader lookup for the value the engine echoes back on
  /// `creative.journey.optStatus`. Unknown or absent values return `null`
  /// (never throws) so response parsing survives future engine values.
  /// Surrounding whitespace is trimmed and case normalized, matching Android's
  /// `JourneyOpt.fromWire`. The engine marshals a typed enum and only emits lowercase, so this is
  /// defensive — but a read path that accepts `"In"` on one platform and `null` on another is a
  /// parity seam regardless of whether today's producer can trigger it.
  static JourneyOpt? fromWire(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'in':
        return JourneyOpt.optIn;
      case 'out':
        return JourneyOpt.optOut;
      default:
        return null;
    }
  }
}

/// Returns a PII-safe rejection reason token when [sessionId] would be
/// silently treated as absent by the decision-engine (disabling Journey),
/// or `null` when it is acceptable.
///
/// The engine trims the value and rejects it when blank-after-trim or longer
/// than 256 UTF-8 bytes (`journey_gate.go`). This never returns the raw value,
/// which is a publisher PII identifier and must not be logged.
String? journeySessionIdRejectionReason(String sessionId) {
  final trimmed = sessionId.trim();
  if (trimmed.isEmpty) return 'blank_after_trim';
  if (utf8.encode(trimmed).length > 256) return 'exceeds_256_bytes';
  return null;
}

class DecisionRequest {
  final List<Placement> placements;
  final Targeting? targeting;
  final User? user;
  final Device? device;
  final App? app;

  /// Stable publisher-provided identifier for the trip/session. Required for
  /// Journey sequencing. Serialized top-level; trimmed, and omitted when blank.
  final String? sessionId;

  /// Explicit Journey opt control for this request. Serialized top-level as
  /// its wire literal (`in`/`out`) only when set.
  final JourneyOpt? journeyOpt;

  DecisionRequest({
    required this.placements,
    this.targeting,
    this.user,
    this.device,
    this.app,
    this.sessionId,
    this.journeyOpt,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'placements': placements.map((p) => p.toJson()).toList(),
      if (targeting != null) 'targeting': targeting!.toJson(),
      if (user != null) 'user': user!.toJson(),
      if (device != null) 'device': device!.toJson(),
      if (app != null) 'app': app!.toJson(),
    };
    // sessionId: trim; omit when blank; send over-length values as-is (the
    // engine is authoritative and records the rejection reason server-side).
    if (sessionId != null) {
      final trimmed = sessionId!.trim();
      if (trimmed.isNotEmpty) json['sessionId'] = trimmed;
    }
    // journeyOpt: only the two engine literals ever reach the wire.
    if (journeyOpt != null) json['journeyOpt'] = journeyOpt!.value;
    return json;
  }
}

class Placement {
  final String key;
  final int? count;
  final Format? format;
  final String? advertiserId;
  final String? templateId;

  Placement({
    required this.key,
    this.count,
    this.format,
    this.advertiserId,
    this.templateId,
  });

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      if (count != null) 'count': count,
      if (format != null) 'format': format!.value,
      if (advertiserId != null) 'advertiserId': advertiserId,
      if (templateId != null) 'templateId': templateId,
    };
  }
}

enum Format {
  native('native'),
  video('video');

  final String value;
  const Format(this.value);
}

/// A rectangle to search inside, in degrees.
///
/// The engine refuses one that crosses the antimeridian, which keeps `west < east` a flat
/// invariant rather than a special case; supporting it later is additive.
class DistanceBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const DistanceBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });
}

/// One Sponsored Pin search: a point, exactly one shape around it, and an optional cap.
///
/// Dart has no method overloading, so the two shapes are two named constructors rather than two
/// `setDistanceTargeting` signatures. The effect is the one iOS and Android get from overloads:
/// a call naming both a radius and a rectangle, or neither, cannot be written.
///
/// The origin stays required for a bounds search, because "nearest first" needs somewhere to
/// measure from and the centre of a rectangle is not necessarily where the viewer is.
///
/// Both constructors validate the origin, the shape and the limit, and deliberately do NOT
/// validate the 50 km radius and 100 km diagonal ceilings: those are server policy, and a client
/// that hard-codes them refuses what a newer engine would accept.
class Distance {
  final double latitude;
  final double longitude;

  /// Radius in **metres**. Null when this is a bounds search.
  final double? radius;
  final DistanceBounds? bounds;

  /// Narrows the campaign's own cap on how many points come back; it can never widen it.
  final int? limit;

  Distance._({
    required this.latitude,
    required this.longitude,
    this.radius,
    this.bounds,
    this.limit,
  });

  /// Asks for the campaign's pins within [radiusMeters] of a point.
  ///
  /// Throws [ArgumentError] on an impossible origin, a radius of zero or less, or a limit of
  /// zero or less.
  factory Distance.radius({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    int? limit,
  }) {
    _validateOrigin(latitude, longitude);
    if (radiusMeters <= 0) {
      throw ArgumentError.value(
          radiusMeters, 'radiusMeters', 'must be greater than 0 metres');
    }
    _validateLimit(limit);
    return Distance._(
      latitude: latitude,
      longitude: longitude,
      radius: radiusMeters,
      limit: limit,
    );
  }

  /// Asks for the campaign's pins inside a rectangle, measured from a point.
  ///
  /// Throws [ArgumentError] on an impossible origin, a rectangle that encloses nothing or
  /// crosses the antimeridian, or a limit of zero or less.
  factory Distance.bounds({
    required double latitude,
    required double longitude,
    required DistanceBounds bounds,
    int? limit,
  }) {
    _validateOrigin(latitude, longitude);
    if (bounds.north < -90 ||
        bounds.north > 90 ||
        bounds.south < -90 ||
        bounds.south > 90 ||
        bounds.east < -180 ||
        bounds.east > 180 ||
        bounds.west < -180 ||
        bounds.west > 180) {
      throw ArgumentError.value(bounds, 'bounds',
          'latitudes must be in [-90, 90] and longitudes in [-180, 180]');
    }
    if (bounds.north <= bounds.south) {
      throw ArgumentError.value(
          bounds, 'bounds', 'require north greater than south');
    }
    // The engine refuses a rectangle crossing the antimeridian, so west < east is flat.
    if (bounds.west >= bounds.east) {
      throw ArgumentError.value(bounds, 'bounds',
          'must not cross the antimeridian: west must be less than east');
    }
    _validateLimit(limit);
    return Distance._(
      latitude: latitude,
      longitude: longitude,
      bounds: bounds,
      limit: limit,
    );
  }

  static void _validateOrigin(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'must be in [-90, 90]');
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
          longitude, 'longitude', 'must be in [-180, 180]');
    }
  }

  static void _validateLimit(int? limit) {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than 0');
    }
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (radius != null) 'radius': radius,
        if (bounds != null)
          'bounds': {
            'north': bounds!.north,
            'south': bounds!.south,
            'east': bounds!.east,
            'west': bounds!.west,
          },
        if (limit != null) 'limit': limit,
      };
}

class Targeting {
  final List<int>? geo;
  final List<Location>? location;
  final List<Destination>? destination;
  final List<CustomKeyValue>? custom;

  /// The Sponsored Pin search (Sponsored Pin Locations, epic #3138). Additive: a request that
  /// omits it behaves exactly as it did before.
  ///
  /// This is **not** [location], which it resembles on the wire and differs from entirely.
  /// `location` is where the viewer is, matched against a fence the advertiser drew, and it
  /// decides whether an Ad may serve at all. `distance` decides which pins a serving creative
  /// carries, and filters no candidate by itself. They compose, and neither implies the other.
  final Distance? distance;

  Targeting({
    this.geo,
    this.location,
    this.destination,
    this.custom,
    this.distance,
  });

  Map<String, dynamic> toJson() {
    return {
      if (geo != null) 'geo': geo,
      if (location != null)
        'location': location!
            .map((l) => {'latitude': l.latitude, 'longitude': l.longitude})
            .toList(),
      // `minConfidence` is the engine's canonical key, matching every other field on the request
      // contract. `min_confidence` survives only as a back-compat alias so already-fielded SDKs
      // keep parsing, and camelCase wins when both are present.
      if (destination != null)
        'destination': destination!
            .map((d) => {
                  'latitude': d.latitude,
                  'longitude': d.longitude,
                  'minConfidence': d.minConfidence,
                })
            .toList(),
      if (custom != null)
        'custom': custom!.map((c) => {'key': c.key, 'value': c.value}).toList(),
      if (distance != null) 'distance': distance!.toJson(),
    };
  }
}

class Location {
  final double latitude;
  final double longitude;

  Location({required this.latitude, required this.longitude});
}

class Destination {
  final double latitude;
  final double longitude;
  final double minConfidence;

  Destination({
    required this.latitude,
    required this.longitude,
    required this.minConfidence,
  });
}

class CustomKeyValue {
  final String key;
  final dynamic value;

  CustomKeyValue({required this.key, required this.value});
}

class User {
  final String? id;
  final String? ip;
  final String? timezone;
  final Consent? consent;

  User({
    this.id,
    this.ip,
    this.timezone,
    this.consent,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (ip != null) 'ip': ip,
      if (timezone != null) 'timezone': timezone,
      if (consent != null) 'consent': consent!.toJson(),
    };
  }
}

class Consent {
  final bool gdpr;

  Consent({this.gdpr = false});

  Map<String, dynamic> toJson() => {'gdpr': gdpr};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Consent &&
          runtimeType == other.runtimeType &&
          gdpr == other.gdpr;

  @override
  int get hashCode => gdpr.hashCode;
}

class Device {
  final String? id;
  final String? model;
  final String? manufacturer;
  final String? os;
  final String? osVersion;
  final String? timezone;
  final String? language;

  Device({
    this.id,
    this.model,
    this.manufacturer,
    this.os,
    this.osVersion,
    this.timezone,
    this.language,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (model != null) 'model': model,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (os != null) 'os': os,
      if (osVersion != null) 'osVersion': osVersion,
      if (timezone != null) 'timezone': timezone,
      if (language != null) 'language': language,
    };
  }
}

class App {
  final String? name;
  final String? version;
  final String? buildNumber;
  final String? identifier;
  final String? language;

  App({
    this.name,
    this.version,
    this.buildNumber,
    this.identifier,
    this.language,
  });

  Map<String, dynamic> toJson() {
    return {
      if (name != null) 'name': name,
      if (version != null) 'version': version,
      if (buildNumber != null) 'buildNumber': buildNumber,
      if (identifier != null) 'identifier': identifier,
      if (language != null) 'language': language,
    };
  }
}
