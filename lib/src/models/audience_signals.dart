// Audience signals: typed values for the audience dimensions the engine can
// target on. Each member's `value` is the exact wire string sent in custom
// targeting (or on the device object). Audience dimensions require the
// SDKConfig `apiVersion` '2025-11-01'.

/// Age bracket of the viewer, in completed years. Wire key `age_group`.
///
/// If the age is unknown, do not set it (leave the setter unset or null).
/// Never guess a bracket.
enum AgeGroup {
  /// Below 18 completed years.
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

/// Gender of the viewer, as the user stated it to you. Wire key `gender`.
/// The SDK and AdMoai never infer it. If it is unknown, do not set it.
enum Gender {
  female('female'),
  male('male'),
  other('other'),

  /// The user's recorded choice not to say. Never a default for missing data:
  /// if you do not know the gender, do not send one.
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

  /// A known account type outside the four named ones. If the type is
  /// unknown, do not send one.
  other('other');

  /// The string sent on the wire.
  final String value;
  const AccountType(this.value);
}

/// Subscription state of the viewer. Wire key `subscription_status`.
enum SubscriptionStatus {
  /// Known: the user has no current or previous subscription. If it is
  /// unknown, do not send a value.
  none('none'),
  trial('trial'),
  active('active'),
  paused('paused'),
  expired('expired');

  /// The string sent on the wire.
  final String value;
  const SubscriptionStatus(this.value);
}

/// Age of the user's account with you (since the account was created). It is
/// not the age of the app install or of the SDK install. Wire key
/// `account_tenure`.
enum AccountTenure {
  days0To30('0_30d'),
  days31To90('31_90d'),
  days91To365('91_365d'),
  days366Plus('366d_plus');

  /// The string sent on the wire.
  final String value;
  const AccountTenure(this.value);
}

/// Completed activities in the trailing 30 x 24 hours. Wire key
/// `activity_frequency_30d`.
///
/// An activity is one completed use of your service (a ride, a parking
/// session, a ticket, a rental). A booking that was not used does not count.
/// The wire value is always a string, including `"0"`.
enum ActivityFrequency30d {
  /// Known: zero completed activities in the window. If the count is unknown,
  /// do not send a value.
  zero('0'),
  times1To2('1_2'),
  times3To9('3_9'),
  times10Plus('10_plus');

  /// The string sent on the wire.
  final String value;
  const ActivityFrequency30d(this.value);
}

/// Time since the viewer's last completed activity, in elapsed days: completed
/// 24-hour periods between UTC instants. Wire key `last_activity_recency`.
///
/// An activity is one completed use of your service. A booking that was not
/// used does not count.
enum LastActivityRecency {
  /// Known: no activity was ever completed. If it is unknown, do not send a
  /// value.
  never('never'),
  days0To7('0_7d'),
  days8To30('8_30d'),
  days31To90('31_90d'),
  days91Plus('91d_plus');

  /// The string sent on the wire.
  final String value;
  const LastActivityRecency(this.value);
}

/// Form factor of the device. Sent as `device.category`. Recorded for
/// reporting: ads cannot target it yet.
enum DeviceCategory {
  phone('phone'),
  tablet('tablet'),
  other('other');

  /// The string sent on the wire.
  final String value;
  const DeviceCategory(this.value);

  /// Parses a wire string. Exact, case-sensitive match only; null and unknown
  /// values yield null.
  static DeviceCategory? fromWire(String? raw) {
    if (raw == null) return null;
    for (final c in values) {
      if (c.value == raw) return c;
    }
    return null;
  }
}

/// Custom-targeting keys used by the audience helpers, for callers that go
/// through the generic `addCustomTargeting`.
abstract final class AudienceSignalKey {
  static const String ageGroup = 'age_group';
  static const String gender = 'gender';
  static const String accountType = 'account_type';
  static const String subscriptionStatus = 'subscription_status';
  static const String accountTenure = 'account_tenure';
  static const String activityFrequency30d = 'activity_frequency_30d';
  static const String lastActivityRecency = 'last_activity_recency';
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
