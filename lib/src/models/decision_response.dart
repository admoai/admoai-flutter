import 'decision_request.dart' show JourneyOpt;

typedef DecisionResponse = List<Decision>;

/// Tolerant Reader helpers: extract a value only when it has the expected
/// type, returning `null` otherwise. These never throw on missing, extra, or
/// retyped fields (docs.admoai.com Tolerant Reader policy).
String? _asString(dynamic v) => v is String ? v : null;
bool? _asBool(dynamic v) => v is bool ? v : null;
int? _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);
Map<String, dynamic>? _asMap(dynamic v) =>
    v is Map<String, dynamic> ? v : null;

class Decision {
  final String placement;
  final List<Creative>? creatives;

  Decision({
    required this.placement,
    this.creatives,
  });

  factory Decision.fromJson(Map<String, dynamic> json) {
    final rawCreatives = json['creatives'];
    return Decision(
      // Tolerant: default to '' rather than throw when placement is
      // missing/retyped (a decision with no placement key is still a valid
      // no-ad shape to a caller).
      placement: _asString(json['placement']) ?? '',
      // Tolerant: only iterate a real list, and skip entries that are not
      // objects. Creative.fromJson is itself total (never throws).
      creatives: rawCreatives is List
          ? rawCreatives
              .map(_asMap)
              .whereType<Map<String, dynamic>>()
              .map(Creative.fromJson)
              .toList()
          : null,
    );
  }
}

extension DecisionNoAd on Decision {
  /// Whether this decision carries a renderable creative. `false` covers both
  /// no-ad shapes the engine emits — `creatives: []` (e.g. single-brand
  /// takeover protection) and `creatives: null` (ordinary no-fill).
  ///
  /// The SDK treats both uniformly as "no ad": render nothing, fire no
  /// tracking, and never substitute a local, cached, or competing ad. The two
  /// shapes are not a stable "protected takeover" signal (the reason is
  /// server-side only), so do not branch on which empty shape was returned.
  bool get hasCreative => creatives != null && creatives!.isNotEmpty;

  /// Inverse of [hasCreative] — a clean no-ad state.
  bool get isNoAd => !hasCreative;
}

class Creative {
  final List<Content> contents;
  final Metadata? metadata;
  final Advertiser advertiser;
  final Template template;
  final Tracking tracking;
  final String? delivery;
  final VastData? vast;
  final List<VerificationScriptResource>? verificationScriptResources;

  /// Read-only Journey metadata, present only for Journey-served creatives
  /// (`null` for normal Ads). The SDK preserves it verbatim and must not use
  /// it to infer stage progression, completion, or billing.
  final CreativeJourney? journey;

  Creative({
    required this.contents,
    this.metadata,
    required this.advertiser,
    required this.template,
    required this.tracking,
    this.delivery,
    this.vast,
    this.verificationScriptResources,
    this.journey,
  });

  /// Tolerant Reader parse: never throws. Missing/retyped required blocks fall
  /// back to safe defaults (empty contents, empty Advertiser/Template, empty
  /// Tracking) and malformed list entries are dropped, so one bad field cannot
  /// drop the whole response. Values the SDK does not recognize are ignored.
  factory Creative.fromJson(Map<String, dynamic> json) {
    final rawContents = json['contents'];
    final rawVerifications = json['verificationScriptResources'];
    return Creative(
      contents: rawContents is List
          ? rawContents
              .map(Content.tryFromJson)
              .whereType<Content>()
              .toList()
          : <Content>[],
      metadata: _asMap(json['metadata']) == null
          ? null
          : Metadata.fromJson(_asMap(json['metadata'])!),
      advertiser: _asMap(json['advertiser']) == null
          ? Advertiser()
          : Advertiser.fromJson(_asMap(json['advertiser'])!),
      template: _asMap(json['template']) == null
          ? Template(key: '')
          : Template.fromJson(_asMap(json['template'])!),
      tracking: _asMap(json['tracking']) == null
          ? Tracking()
          : Tracking.fromJson(_asMap(json['tracking'])!),
      delivery: _asString(json['delivery']),
      vast: _asMap(json['vast']) == null
          ? null
          : VastData.fromJson(_asMap(json['vast'])!),
      verificationScriptResources: rawVerifications is List
          ? rawVerifications
              .map(VerificationScriptResource.tryFromJson)
              .whereType<VerificationScriptResource>()
              .toList()
          : null,
      journey: _asMap(json['journey']) == null
          ? null
          : CreativeJourney.fromJson(_asMap(json['journey'])!),
    );
  }
}

/// Read-only Journey Takeover Ads metadata attached to a Journey-served
/// [Creative] under the response key `journey`. Field names match the
/// decision-engine v20251101 `CreativeJourney` contract exactly.
///
/// Every field is nullable and parsed defensively (Tolerant Reader policy):
/// unknown/missing/retyped fields degrade to `null` and never throw, so older
/// and newer SDK builds survive additive engine evolution without a version
/// bump. All values are server-owned and read-only.
class CreativeJourney {
  final String? dealId;
  final String? instanceId;
  final String? definitionKey;
  final String? stageId;
  final String? stageKey;
  final String? stageNodeId;
  final String? sessionId;

  /// Effective opt status echoed by the engine. Parsed as an open set:
  /// unknown/absent values are `null` (malformed/unknown — not a business
  /// state; valid engine values are `in`/`out`).
  final JourneyOpt? optStatus;

  /// True only on the serve that completes a `final_stage` Journey. For
  /// `custom_event` deals this is `false` and completion is signalled via
  /// `tracking.completions` instead.
  final bool? isCompletion;

  /// Open-set strings (kept raw to tolerate future engine values).
  final String? pricingModel;
  final String? fallbackBillingMode;

  CreativeJourney({
    this.dealId,
    this.instanceId,
    this.definitionKey,
    this.stageId,
    this.stageKey,
    this.stageNodeId,
    this.sessionId,
    this.optStatus,
    this.isCompletion,
    this.pricingModel,
    this.fallbackBillingMode,
  });

  factory CreativeJourney.fromJson(Map<String, dynamic> json) {
    return CreativeJourney(
      dealId: _asString(json['dealId']),
      instanceId: _asString(json['instanceId']),
      definitionKey: _asString(json['definitionKey']),
      stageId: _asString(json['stageId']),
      stageKey: _asString(json['stageKey']),
      stageNodeId: _asString(json['stageNodeId']),
      sessionId: _asString(json['sessionId']),
      optStatus: JourneyOpt.fromWire(_asString(json['optStatus'])),
      isCompletion: _asBool(json['isCompletion']),
      pricingModel: _asString(json['pricingModel']),
      fallbackBillingMode: _asString(json['fallbackBillingMode']),
    );
  }
}

class VerificationScriptResource {
  final String vendorKey;
  final String scriptUrl;
  final String? verificationParameters;

  VerificationScriptResource({
    required this.vendorKey,
    required this.scriptUrl,
    this.verificationParameters,
  });

  factory VerificationScriptResource.fromJson(Map<String, dynamic> json) {
    return VerificationScriptResource(
      vendorKey: _asString(json['vendorKey']) ?? '',
      scriptUrl: _asString(json['scriptUrl']) ?? '',
      verificationParameters: _asString(json['verificationParameters']),
    );
  }

  /// Tolerant Reader variant: returns `null` (instead of throwing or yielding a
  /// useless entry) when the item is not an object or lacks a usable
  /// `vendorKey`/`scriptUrl`. Used by [Creative.fromJson] to drop malformed
  /// verification entries without failing the whole parse.
  static VerificationScriptResource? tryFromJson(dynamic json) {
    final map = _asMap(json);
    if (map == null) return null;
    final vendorKey = _asString(map['vendorKey']);
    final scriptUrl = _asString(map['scriptUrl']);
    if (vendorKey == null || scriptUrl == null) return null;
    return VerificationScriptResource(
      vendorKey: vendorKey,
      scriptUrl: scriptUrl,
      verificationParameters: _asString(map['verificationParameters']),
    );
  }
}

class Content {
  final String key;
  final dynamic value;
  final String type;

  Content({
    required this.key,
    required this.value,
    required this.type,
  });

  factory Content.fromJson(Map<String, dynamic> json) {
    return Content(
      key: _asString(json['key']) ?? '',
      value: json['value'],
      type: _asString(json['type']) ?? '',
    );
  }

  /// Tolerant Reader variant: returns `null` when the entry is not an object or
  /// has no usable `key`/`type`. Used by [Creative.fromJson] to drop malformed
  /// content entries rather than throw. (`value` is passed through as-is.)
  static Content? tryFromJson(dynamic json) {
    final map = _asMap(json);
    if (map == null) return null;
    final key = _asString(map['key']);
    final type = _asString(map['type']);
    if (key == null || type == null) return null;
    return Content(key: key, value: map['value'], type: type);
  }
}

extension ContentListExtension on List<Content> {
  Content? getContent(String key) =>
      where((c) => c.key == key).firstOrNull;

  bool hasContents() => isNotEmpty;

  bool isType(String key, String type) =>
      any((c) => c.key == key && c.type == type);
}

class Metadata {
  final String adId;
  final String creativeId;
  final String? advertiserId;
  final String templateId;
  final String placementId;

  /// Render-level attribution key the engine mints per served creative
  /// (`impId`). Present on Journey serves, `null` for normal ads.
  ///
  /// Read-only passthrough of the engine contract, for reconciling a specific
  /// render against reporting. The encrypted tracking token remains the
  /// authoritative source server-side — this is not a substitute for it, and the
  /// SDK never derives anything from it.
  final String? impId;

  final String priority;
  final String? language;
  final int? duration;
  final String? aspectRatio;
  final bool? isSkippable;

  /// Seconds before a skippable video may be skipped (`skipOffsetSeconds`).
  final int? skipOffsetSeconds;

  /// End-card presentation mode for video creatives (`endCardMode`). Kept as a
  /// raw open-set string to tolerate future engine values.
  final String? endCardMode;

  final String? format;
  final String? style;

  Metadata({
    required this.adId,
    required this.creativeId,
    this.advertiserId,
    required this.templateId,
    required this.placementId,
    this.impId,
    required this.priority,
    this.language,
    this.duration,
    this.aspectRatio,
    this.isSkippable,
    this.skipOffsetSeconds,
    this.endCardMode,
    this.format,
    this.style,
  });

  /// Tolerant Reader parse: never throws. Currently-required id fields default
  /// to `''` when missing/retyped (preserving the non-null public API rather
  /// than a source-breaking widening to nullable); optional fields degrade to
  /// `null`.
  factory Metadata.fromJson(Map<String, dynamic> json) {
    return Metadata(
      adId: _asString(json['adId']) ?? '',
      creativeId: _asString(json['creativeId']) ?? '',
      advertiserId: _asString(json['advertiserId']),
      templateId: _asString(json['templateId']) ?? '',
      placementId: _asString(json['placementId']) ?? '',
      impId: _asString(json['impId']),
      priority: _asString(json['priority']) ?? '',
      language: _asString(json['language']),
      duration: _asInt(json['duration']),
      aspectRatio: _asString(json['aspectRatio']),
      isSkippable: _asBool(json['isSkippable']),
      skipOffsetSeconds: _asInt(json['skipOffsetSeconds']),
      endCardMode: _asString(json['endCardMode']),
      format: _asString(json['format']),
      style: _asString(json['style']),
    );
  }
}

class Advertiser {
  final String? id;
  final String? name;
  final String? legalName;
  final String? logoUrl;

  Advertiser({
    this.id,
    this.name,
    this.legalName,
    this.logoUrl,
  });

  factory Advertiser.fromJson(Map<String, dynamic> json) {
    return Advertiser(
      id: _asString(json['id']),
      name: _asString(json['name']),
      legalName: _asString(json['legalName']),
      logoUrl: _asString(json['logoUrl']),
    );
  }
}

class Template {
  final String key;
  final String? style;

  Template({
    required this.key,
    this.style,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      key: _asString(json['key']) ?? '',
      style: _asString(json['style']),
    );
  }
}

class Tracking {
  final List<TrackingItem>? impressions;
  final List<TrackingItem>? clicks;
  final List<TrackingItem>? custom;
  final List<TrackingItem>? videoEvents;

  /// Journey completion tracking URLs. Populated only for Journey deals using
  /// `completion_strategy = 'custom_event'`; the SDK fires the matching entry
  /// once when the publisher-mapped completion action occurs. Empty/absent for
  /// `final_stage` deals (completion is recorded server-side) and normal Ads.
  final List<TrackingItem>? completions;

  Tracking({
    this.impressions,
    this.clicks,
    this.custom,
    this.videoEvents,
    this.completions,
  });

  factory Tracking.fromJson(Map<String, dynamic> json) {
    return Tracking(
      impressions: _trackingList(json['impressions']),
      clicks: _trackingList(json['clicks']),
      custom: _trackingList(json['custom']),
      videoEvents: _trackingList(json['videoEvents']),
      completions: _trackingList(json['completions']),
    );
  }

  /// Tolerant Reader list parse: returns `null` when the value is not a list,
  /// and silently drops individual entries that are missing/retyped `key`/`url`
  /// rather than throwing. Keeps a malformed entry from breaking the whole
  /// response — important for `completions` (new Journey code) and consistent
  /// across all tracking categories.
  static List<TrackingItem>? _trackingList(dynamic value) {
    if (value is! List) return null;
    return value
        .map(TrackingItem.tryFromJson)
        .whereType<TrackingItem>()
        .toList();
  }

  bool hasTrackingFor(TrackingType type, String key) {
    switch (type) {
      case TrackingType.impression:
        return impressions?.any((item) => item.key == key) ?? false;
      case TrackingType.click:
        return clicks?.any((item) => item.key == key) ?? false;
      case TrackingType.custom:
        return custom?.any((item) => item.key == key) ?? false;
      case TrackingType.videoEvent:
        return videoEvents?.any((item) => item.key == key) ?? false;
      case TrackingType.completion:
        return completions?.any((item) => item.key == key) ?? false;
    }
  }

  String? getTrackingUrl(TrackingType type, String key) {
    switch (type) {
      case TrackingType.impression:
        return getImpressionUrl(key: key);
      case TrackingType.click:
        return getClickUrl(key: key);
      case TrackingType.custom:
        return getCustomUrl(key: key);
      case TrackingType.videoEvent:
        return getVideoEventUrl(key: key);
      case TrackingType.completion:
        return getCompletionUrl(key: key);
    }
  }

  String? getImpressionUrl({String key = 'default'}) {
    return impressions?.where((item) => item.key == key).firstOrNull?.url;
  }

  String? getClickUrl({String key = 'default'}) {
    return clicks?.where((item) => item.key == key).firstOrNull?.url;
  }

  String? getCustomUrl({required String key}) {
    return custom?.where((item) => item.key == key).firstOrNull?.url;
  }

  String? getVideoEventUrl({required String key}) {
    return videoEvents?.where((item) => item.key == key).firstOrNull?.url;
  }

  String? getCompletionUrl({required String key}) {
    return completions?.where((item) => item.key == key).firstOrNull?.url;
  }
}

class TrackingItem {
  final String key;
  final String url;

  TrackingItem({
    required this.key,
    required this.url,
  });

  factory TrackingItem.fromJson(Map<String, dynamic> json) {
    return TrackingItem(
      key: json['key'] as String,
      url: json['url'] as String,
    );
  }

  /// Tolerant Reader variant: returns `null` (instead of throwing) when the
  /// entry is not a map or is missing/retyped `key`/`url`. Used by
  /// [Tracking._trackingList] so one malformed entry cannot break the whole
  /// response parse.
  static TrackingItem? tryFromJson(dynamic json) {
    if (json is! Map) return null;
    final key = json['key'];
    final url = json['url'];
    if (key is! String || url is! String) return null;
    return TrackingItem(key: key, url: url);
  }
}

enum TrackingType {
  impression('impression'),
  click('click'),
  custom('custom'),
  videoEvent('videoEvent'),
  completion('completion');

  final String value;
  const TrackingType(this.value);
}

class VastData {
  final String? tagUrl;
  final String? xmlBase64;

  VastData({
    this.tagUrl,
    this.xmlBase64,
  });

  factory VastData.fromJson(Map<String, dynamic> json) {
    return VastData(
      tagUrl: _asString(json['tagUrl']),
      xmlBase64: _asString(json['xmlBase64']),
    );
  }
}
