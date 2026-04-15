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

  bool isSkippable() {
    try {
      final content = contents.firstWhere(
        (c) => c.key == 'isSkippable',
        orElse: () => Content(key: '', value: false, type: ''),
      );
      if (content.key.isEmpty) return false;
      return content.value == true || content.value == 'true';
    } catch (e) {
      return false;
    }
  }

  String? getSkipOffset() {
    try {
      final content = contents.firstWhere(
        (c) => c.key == 'skipOffset',
        orElse: () => Content(key: '', value: null, type: ''),
      );
      if (content.key.isEmpty) return null;
      return content.value?.toString();
    } catch (e) {
      return null;
    }
  }
}
