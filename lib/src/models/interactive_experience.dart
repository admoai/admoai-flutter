/// Lead Generation (interactive experience) opt-in, request extension and the
/// per-creative descriptor.
///
/// The wire names of [StandardAttributeKey] are the contract pack's
/// `standard-fields.json` `prefillKeys`, in the same order.
library;

/// A standard attribute an app may be able to fill into a Lead Generation form.
enum StandardAttributeKey {
  firstName('firstName'),
  lastName('lastName'),
  fullName('fullName'),
  email('email'),
  phone('phone'),
  age('age'),
  gender('gender');

  /// The exact catalog key sent and received on the wire.
  final String wireName;

  const StandardAttributeKey(this.wireName);

  /// Exact match on [wireName]; unknown or `null` is `null`. Never throws.
  static StandardAttributeKey? fromWire(String? value) {
    if (value == null) return null;
    for (final key in values) {
      if (key.wireName == value) return key;
    }
    return null;
  }
}

/// Supplies the standard attributes the app could fill into a Lead Generation
/// form. Only the keys are read, when a decision request is built. The value
/// lookup is added when forms can open; an app with no prefill returns an empty
/// set.
abstract interface class LeadFormValueProvider {
  /// The keys the app could fill for the current user.
  Set<StandardAttributeKey> get availableKeys;
}

/// The `interactiveExperience` object of a decision request.
class InteractiveExperienceCapability {
  /// Always `true` when constructed by the SDK.
  final bool supported;

  /// Deduplicated, in [StandardAttributeKey] declaration order.
  final List<StandardAttributeKey> availableAttributeKeys;

  InteractiveExperienceCapability({
    required Iterable<StandardAttributeKey> availableAttributeKeys,
  }) : supported = true,
       availableAttributeKeys = List.unmodifiable(
         StandardAttributeKey.values.where(
           availableAttributeKeys.toSet().contains,
         ),
       );

  Map<String, dynamic> toJson() => {
    'supported': supported,
    'availableAttributeKeys': [
      for (final key in availableAttributeKeys) key.wireName,
    ],
  };
}

/// The interactive experience a creative carries. `null` on a creative means an
/// ordinary creative; see [tryFromJson].
sealed class InteractiveExperience {
  const InteractiveExperience();

  String? get type;

  /// Never throws. `null` input is `null` (absent); anything this SDK cannot
  /// open is an [UnsupportedInteractiveExperience].
  static InteractiveExperience? tryFromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return const UnsupportedInteractiveExperience(type: null);
    final type = raw['type'];
    if (type is! String) {
      return const UnsupportedInteractiveExperience(type: null);
    }
    if (type != LeadGenerationExperience.wireType) {
      return UnsupportedInteractiveExperience(type: type);
    }
    return LeadGenerationExperience._tryFromJson(raw) ??
        UnsupportedInteractiveExperience(type: type);
  }
}

/// A Lead Generation form the app may open for this creative.
final class LeadGenerationExperience extends InteractiveExperience {
  static const String wireType = 'lead_generation';

  final String formId;
  final String preparedVersionId;
  final String formInstanceId;
  final Uri _launchUrl;
  final String _preparationToken;

  /// UTC.
  final DateTime expiresAt;

  /// Keys this form asks to prefill, in server order, known keys only.
  final List<StandardAttributeKey> prefillAttributeKeys;

  const LeadGenerationExperience({
    required this.formId,
    required this.preparedVersionId,
    required this.formInstanceId,
    required Uri launchUrl,
    required String preparationToken,
    required this.expiresAt,
    this.prefillAttributeKeys = const <StandardAttributeKey>[],
  }) : _launchUrl = launchUrl,
       _preparationToken = preparationToken;

  @override
  String get type => wireType;

  static String? _nonBlank(dynamic v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static LeadGenerationExperience? _tryFromJson(Map raw) {
    final formId = _nonBlank(raw['formId']);
    final preparedVersionId = _nonBlank(raw['preparedVersionId']);
    final formInstanceId = _nonBlank(raw['formInstanceId']);
    final token = _nonBlank(raw['preparationToken']);
    final rawUrl = raw['launchUrl'];
    final rawExpiry = raw['expiresAt'];
    final launchUrl = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final expiresAt = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
    final rawKeys = raw['prefillAttributeKeys'];
    if (formId == null ||
        preparedVersionId == null ||
        formInstanceId == null ||
        token == null ||
        launchUrl == null ||
        launchUrl.scheme != 'https' ||
        launchUrl.host.isEmpty ||
        expiresAt == null ||
        (rawKeys != null && rawKeys is! List)) {
      return null;
    }
    final keys = <StandardAttributeKey>[];
    for (final entry in (rawKeys as List? ?? const [])) {
      final key = entry is String ? StandardAttributeKey.fromWire(entry) : null;
      if (key != null && !keys.contains(key)) keys.add(key);
    }
    return LeadGenerationExperience(
      formId: formId,
      preparedVersionId: preparedVersionId,
      formInstanceId: formInstanceId,
      launchUrl: launchUrl,
      preparationToken: token,
      expiresAt: expiresAt.toUtc(),
      prefillAttributeKeys: List.unmodifiable(keys),
    );
  }

  @override
  String toString() =>
      'LeadGenerationExperience(formId: $formId, '
      'formInstanceId: $formInstanceId, '
      'expiresAt: ${expiresAt.toIso8601String()})';
}

/// SDK-internal: the launch URL and preparation token of [experience]. Not part
/// of the public API (hidden from the package export).
({Uri launchUrl, String preparationToken}) leadGenerationLaunch(
  LeadGenerationExperience experience,
) => (
  launchUrl: experience._launchUrl,
  preparationToken: experience._preparationToken,
);

/// An experience this SDK cannot open: an unknown `type`, or a `lead_generation`
/// descriptor that is malformed. The app must treat the creative as not
/// openable: no dead click, no guessed URL.
final class UnsupportedInteractiveExperience extends InteractiveExperience {
  @override
  final String? type;

  const UnsupportedInteractiveExperience({required this.type});

  @override
  String toString() => 'UnsupportedInteractiveExperience(type: $type)';
}
