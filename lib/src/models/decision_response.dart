import 'decision_request.dart' show JourneyOpt;

typedef DecisionResponse = List<Decision>;

/// Tolerant Reader helpers: extract a value only when it has the expected
/// type, returning `null` otherwise. These never throw on missing, extra, or
/// retyped fields (docs.admoai.com Tolerant Reader policy).
String? _asString(dynamic v) => v is String ? v : null;
bool? _asBool(dynamic v) => v is bool ? v : null;

class Decision {
  final String placement;
  final List<Creative>? creatives;

  Decision({
    required this.placement,
    this.creatives,
  });

  factory Decision.fromJson(Map<String, dynamic> json) {
    return Decision(
      placement: json['placement'] as String,
      creatives: (json['creatives'] as List?)
          ?.map((e) => Creative.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
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

  factory Creative.fromJson(Map<String, dynamic> json) {
    return Creative(
      contents: (json['contents'] as List)
          .map((e) => Content.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] == null
          ? null
          : Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      advertiser:
          Advertiser.fromJson(json['advertiser'] as Map<String, dynamic>),
      template: Template.fromJson(json['template'] as Map<String, dynamic>),
      tracking: Tracking.fromJson(json['tracking'] as Map<String, dynamic>),
      delivery: json['delivery'] as String?,
      vast: json['vast'] == null
          ? null
          : VastData.fromJson(json['vast'] as Map<String, dynamic>),
      verificationScriptResources:
          (json['verificationScriptResources'] as List?)
              ?.map((e) =>
                  VerificationScriptResource.fromJson(e as Map<String, dynamic>))
              .toList(),
      // Tolerant: only parse when the block is a map; absent/retyped -> null.
      journey: json['journey'] is Map<String, dynamic>
          ? CreativeJourney.fromJson(json['journey'] as Map<String, dynamic>)
          : null,
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
      vendorKey: json['vendorKey'] as String,
      scriptUrl: json['scriptUrl'] as String,
      verificationParameters: json['verificationParameters'] as String?,
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
      key: json['key'] as String,
      value: json['value'],
      type: json['type'] as String,
    );
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
  final String priority;
  final String? language;
  final int? duration;
  final String? aspectRatio;
  final bool? isSkippable;
  final String? format;
  final String? style;

  Metadata({
    required this.adId,
    required this.creativeId,
    this.advertiserId,
    required this.templateId,
    required this.placementId,
    required this.priority,
    this.language,
    this.duration,
    this.aspectRatio,
    this.isSkippable,
    this.format,
    this.style,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) {
    return Metadata(
      adId: json['adId'] as String,
      creativeId: json['creativeId'] as String,
      advertiserId: json['advertiserId'] as String?,
      templateId: json['templateId'] as String,
      placementId: json['placementId'] as String,
      priority: json['priority'] as String,
      language: json['language'] as String?,
      duration: json['duration'] as int?,
      aspectRatio: json['aspectRatio'] as String?,
      isSkippable: json['isSkippable'] as bool?,
      format: json['format'] as String?,
      style: json['style'] as String?,
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
      id: json['id'] as String?,
      name: json['name'] as String?,
      legalName: json['legalName'] as String?,
      logoUrl: json['logoUrl'] as String?,
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
      key: json['key'] as String,
      style: json['style'] as String?,
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
      impressions: (json['impressions'] as List?)
          ?.map((e) => TrackingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      clicks: (json['clicks'] as List?)
          ?.map((e) => TrackingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      custom: (json['custom'] as List?)
          ?.map((e) => TrackingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      videoEvents: (json['videoEvents'] as List?)
          ?.map((e) => TrackingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      completions: (json['completions'] as List?)
          ?.map((e) => TrackingItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
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
      tagUrl: json['tagUrl'] as String?,
      xmlBase64: json['xmlBase64'] as String?,
    );
  }
}
