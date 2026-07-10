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
  static JourneyOpt? fromWire(String? value) {
    switch (value) {
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

class Targeting {
  final List<int>? geo;
  final List<Location>? location;
  final List<Destination>? destination;
  final List<CustomKeyValue>? custom;

  Targeting({
    this.geo,
    this.location,
    this.destination,
    this.custom,
  });

  Map<String, dynamic> toJson() {
    return {
      if (geo != null) 'geo': geo,
      if (location != null)
        'location': location!
            .map((l) => {'latitude': l.latitude, 'longitude': l.longitude})
            .toList(),
      if (destination != null)
        'destination': destination!
            .map((d) => {
                  'latitude': d.latitude,
                  'longitude': d.longitude,
                  'min_confidence': d.minConfidence,
                })
            .toList(),
      if (custom != null)
        'custom': custom!.map((c) => {'key': c.key, 'value': c.value}).toList(),
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
