// Audience signals: typed values for the audience dimensions the engine can
// target on. Each member's `value` is the exact wire string sent in custom
// targeting (or on the device object). Audience dimensions require the
// SDKConfig `apiVersion` '2025-11-01'.

/// Age bracket of the viewer. Wire key `age_group`.
enum AgeGroup {
  under18('under_18'),
  age18To24('18_24'),
  age25To34('25_34'),
  age35To44('35_44'),
  age45To54('45_54'),
  age55To64('55_64'),
  age65Plus('65_plus');

  /// The string sent on the wire.
  final String value;
  const AgeGroup(this.value);
}

/// Gender of the viewer. Wire key `gender`.
enum Gender {
  female('female'),
  male('male'),
  other('other'),
  preferNotToSay('prefer_not_to_say');

  /// The string sent on the wire.
  final String value;
  const Gender(this.value);
}

/// Kind of account the viewer holds. Wire key `account_type`.
enum AccountType {
  personal('personal'),
  business('business'),
  family('family'),
  student('student'),
  other('other');

  /// The string sent on the wire.
  final String value;
  const AccountType(this.value);
}

/// Subscription state of the viewer. Wire key `subscription_status`.
enum SubscriptionStatus {
  none('none'),
  trial('trial'),
  active('active'),
  paused('paused'),
  expired('expired');

  /// The string sent on the wire.
  final String value;
  const SubscriptionStatus(this.value);
}

/// How long the account has existed. Wire key `account_tenure`.
enum AccountTenure {
  days0To30('0_30d'),
  days31To90('31_90d'),
  days91To365('91_365d'),
  days366Plus('366d_plus');

  /// The string sent on the wire.
  final String value;
  const AccountTenure(this.value);
}

/// Trips taken in the last 30 days. Wire key `trip_frequency_30d`.
/// The wire value is always a string, including `"0"`.
enum TripFrequency30d {
  zero('0'),
  trips1To2('1_2'),
  trips3To9('3_9'),
  trips10Plus('10_plus');

  /// The string sent on the wire.
  final String value;
  const TripFrequency30d(this.value);
}

/// Time since the viewer's last trip. Wire key `last_trip_recency`.
enum LastTripRecency {
  never('never'),
  days0To7('0_7d'),
  days8To30('8_30d'),
  days31To90('31_90d'),
  days91Plus('91d_plus');

  /// The string sent on the wire.
  final String value;
  const LastTripRecency(this.value);
}

/// Form factor of the device. Sent as `device.category`.
enum DeviceCategory {
  phone('phone'),
  tablet('tablet'),
  other('other');

  /// The string sent on the wire.
  final String value;
  const DeviceCategory(this.value);
}

/// Custom-targeting keys used by the audience helpers, for callers that go
/// through the generic `addCustomTargeting`.
abstract final class AudienceSignalKey {
  static const String ageGroup = 'age_group';
  static const String gender = 'gender';
  static const String accountType = 'account_type';
  static const String subscriptionStatus = 'subscription_status';
  static const String accountTenure = 'account_tenure';
  static const String tripFrequency30d = 'trip_frequency_30d';
  static const String lastTripRecency = 'last_trip_recency';
  static const String publisherSegments = 'publisher_segments';
}

/// Normalizes a carrier name: trims it, and treats null, empty and the
/// placeholders `--`, `unknown`, `wifi`, `wi-fi` (case-insensitive) as absent.
String? normalizeCarrier(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  switch (trimmed.toLowerCase()) {
    case '--':
    case 'unknown':
    case 'wifi':
    case 'wi-fi':
      return null;
  }
  return trimmed;
}
