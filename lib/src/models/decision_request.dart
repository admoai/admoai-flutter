class DecisionRequest {
  final List<Placement> placements;
  final Targeting? targeting;
  final User? user;
  final Device? device;
  final App? app;

  DecisionRequest({
    required this.placements,
    this.targeting,
    this.user,
    this.device,
    this.app,
  });

  Map<String, dynamic> toJson() {
    return {
      'placements': placements.map((p) => p.toJson()).toList(),
      if (targeting != null) 'targeting': targeting!.toJson(),
      if (user != null) 'user': user!.toJson(),
      if (device != null) 'device': device!.toJson(),
      if (app != null) 'app': app!.toJson(),
    };
  }
}

class Placement {
  final String key;
  final int count;
  final Format format;
  final String? advertiserId;
  final String? templateId;

  Placement({
    required this.key,
    this.count = 1,
    this.format = Format.native,
    this.advertiserId,
    this.templateId,
  });

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'count': count,
      'format': format.value,
      if (advertiserId != null) 'advertiserId': advertiserId,
      if (templateId != null) 'templateId': templateId,
    };
  }
}

enum Format {
  native('native');

  final String value;
  const Format(this.value);
}

class Targeting {
  final List<int>? geo;
  final List<Location>? location;
  final List<CustomKeyValue>? custom;

  Targeting({
    this.geo,
    this.location,
    this.custom,
  });

  Map<String, dynamic> toJson() {
    return {
      if (geo != null) 'geo': geo,
      if (location != null)
        'location': location!
            .map((l) => {'latitude': l.latitude, 'longitude': l.longitude})
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
