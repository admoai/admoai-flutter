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

  Creative({
    required this.contents,
    this.metadata,
    required this.advertiser,
    required this.template,
    required this.tracking,
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
  final String advertiserId;
  final String templateId;
  final String placementId;
  final String priority;
  final String language;

  Metadata({
    required this.adId,
    required this.creativeId,
    required this.advertiserId,
    required this.templateId,
    required this.placementId,
    required this.priority,
    required this.language,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) {
    return Metadata(
      adId: json['adId'] as String,
      creativeId: json['creativeId'] as String,
      advertiserId: json['advertiserId'] as String,
      templateId: json['templateId'] as String,
      placementId: json['placementId'] as String,
      priority: json['priority'] as String,
      language: json['language'] as String,
    );
  }
}

class Advertiser {
  final String name;
  final String legalName;
  final String logoUrl;

  Advertiser({
    required this.name,
    required this.legalName,
    required this.logoUrl,
  });

  factory Advertiser.fromJson(Map<String, dynamic> json) {
    return Advertiser(
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

  Tracking({
    required this.impressions,
    this.clicks,
    this.custom,
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
  custom('custom');

  final String value;
  const TrackingType(this.value);
}
