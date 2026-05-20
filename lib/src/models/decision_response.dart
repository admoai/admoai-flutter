typedef DecisionResponse = List<Decision>;

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

  Creative({
    required this.contents,
    this.metadata,
    required this.advertiser,
    required this.template,
    required this.tracking,
    this.delivery,
    this.vast,
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
  Content? getContent(String key) => firstWhere((c) => c.key == key);

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
  final String name;
  final String legalName;
  final String logoUrl;

  Advertiser({
    this.id,
    required this.name,
    required this.legalName,
    required this.logoUrl,
  });

  factory Advertiser.fromJson(Map<String, dynamic> json) {
    return Advertiser(
      id: json['id'] as String?,
      name: json['name'] as String,
      legalName: json['legalName'] as String,
      logoUrl: json['logoUrl'] as String,
    );
  }
}

class Template {
  final String key;
  final String style;

  Template({
    required this.key,
    required this.style,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      key: json['key'] as String,
      style: json['style'] as String,
    );
  }
}

class Tracking {
  final List<TrackingItem> impressions;
  final List<TrackingItem>? clicks;
  final List<TrackingItem>? custom;
  final List<TrackingItem>? videoEvents;

  Tracking({
    required this.impressions,
    this.clicks,
    this.custom,
    this.videoEvents,
  });

  factory Tracking.fromJson(Map<String, dynamic> json) {
    return Tracking(
      impressions: (json['impressions'] as List)
          .map((e) => TrackingItem.fromJson(e as Map<String, dynamic>))
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
    );
  }

  bool hasTrackingFor(TrackingType type, String key) {
    switch (type) {
      case TrackingType.impression:
        return impressions.any((item) => item.key == key);
      case TrackingType.click:
        return clicks?.any((item) => item.key == key) ?? false;
      case TrackingType.custom:
        return custom?.any((item) => item.key == key) ?? false;
      case TrackingType.videoEvent:
        return videoEvents?.any((item) => item.key == key) ?? false;
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
    }
  }

  String? getImpressionUrl({String key = 'default'}) {
    return impressions.firstWhere((item) => item.key == key).url;
  }

  String? getClickUrl({String key = 'default'}) {
    return clicks?.firstWhere((item) => item.key == key).url;
  }

  String? getCustomUrl({required String key}) {
    return custom?.firstWhere((item) => item.key == key).url;
  }

  String? getVideoEventUrl({required String key}) {
    return videoEvents?.firstWhere((item) => item.key == key).url;
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
  videoEvent('videoEvent');

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
