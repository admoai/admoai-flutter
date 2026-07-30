import 'dart:convert';
import '../models/decision_response.dart';

extension VideoHelper on Creative {
  bool isVastTagDelivery() => delivery == 'vast_tag';

  bool isVastXmlDelivery() => delivery == 'vast_xml';

  bool isJsonDelivery() => delivery == 'json';

  String? getVastTagUrl({String? mediaType, String? mediaDelivery}) {
    final baseUrl = vast?.tagUrl;
    if (baseUrl == null) return null;

    final queryParams = <String>[];
    if (mediaType != null) {
      queryParams.add('mediaType=${Uri.encodeComponent(mediaType)}');
    }
    if (mediaDelivery != null) {
      queryParams.add('mediaDelivery=${Uri.encodeComponent(mediaDelivery)}');
    }

    if (queryParams.isEmpty) {
      return baseUrl;
    }

    final separator = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl$separator${queryParams.join('&')}';
  }

  String? getVastXmlBase64({String? mediaType, String? mediaDelivery}) {
    final base64Xml = vast?.xmlBase64;
    if (base64Xml == null) return null;

    if (mediaType == null && mediaDelivery == null) {
      return base64Xml;
    }

    try {
      final decodedBytes = base64Decode(base64Xml);
      var xmlString = utf8.decode(decodedBytes);

      final mediaFilePattern = RegExp(
        r'(<MediaFile[^>]*?)(\s+type="[^"]*")?(\s+delivery="[^"]*")?([^>]*?>)',
      );

      xmlString = xmlString.replaceAllMapped(mediaFilePattern, (match) {
        var result = match.group(0)!;

        if (mediaType != null) {
          if (result.contains('type=')) {
            result = result.replaceAll(
              RegExp(r'type="[^"]*"'),
              'type="$mediaType"',
            );
          } else {
            result = result.replaceAll('>', ' type="$mediaType">');
          }
        }

        if (mediaDelivery != null) {
          if (result.contains('delivery=')) {
            result = result.replaceAll(
              RegExp(r'delivery="[^"]*"'),
              'delivery="$mediaDelivery"',
            );
          } else {
            result = result.replaceAll('>', ' delivery="$mediaDelivery">');
          }
        }

        return result;
      });

      return base64Encode(utf8.encode(xmlString));
    } catch (e) {
      return base64Xml;
    }
  }

  /// Whether the video may be skipped.
  ///
  /// Prefers `metadata.isSkippable` — the engine-owned field, and the only source
  /// the iOS SDK reads — then falls back to the creative's content fields.
  ///
  /// The fallback matches **both** `isSkippable` and `is_skippable`. It previously
  /// matched camelCase only, while the platform creates template fields in
  /// snake_case (`is_skippable`), so it could never hit and this method always
  /// returned `false`. That is the same class of defect as adhub #2483, where the
  /// journey click resolver matched a hand-maintained snake_case list while the
  /// platform wrote camelCase — the same seam, the opposite direction.
  bool isSkippable() {
    final fromMetadata = metadata?.isSkippable;
    if (fromMetadata != null) return fromMetadata;

    final content = contents.getContent('isSkippable') ??
        contents.getContent('is_skippable');
    return _asFlag(content?.value);
  }

  /// Seconds before a skippable video may be skipped, as a string.
  ///
  /// Prefers `metadata.skipOffsetSeconds`, then falls back to the creative's
  /// content fields, matching both `skipOffset` and `skip_offset` for the reason
  /// above.
  ///
  /// Returns a `String?` to stay source-compatible; read
  /// `creative.metadata?.skipOffsetSeconds` for a typed `int?`.
  String? getSkipOffset() {
    final fromMetadata = metadata?.skipOffsetSeconds;
    if (fromMetadata != null) return fromMetadata.toString();

    final content =
        contents.getContent('skipOffset') ?? contents.getContent('skip_offset');
    return content?.value?.toString();
  }
}

/// Interprets a content value as a boolean flag.
///
/// The template field backing skippability is typed `integer`, so the value can
/// arrive as a bool, a number, or a string depending on the template and the
/// producer. Anything unrecognized is `false` — never a throw.
bool _asFlag(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}
