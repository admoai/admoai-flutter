import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;

class VastParser {
  static Future<List<String>> parseVastTagUrl(String tagUrl) async {
    try {
      final response = await http.get(Uri.parse(tagUrl));
      if (response.statusCode != 200) return [];
      return _parseVastXml(response.body);
    } catch (e) {
      return [];
    }
  }

  static List<String> parseVastXmlBase64(String base64Xml) {
    try {
      final xmlString = utf8.decode(base64.decode(base64Xml));
      return _parseVastXml(xmlString);
    } catch (e) {
      return [];
    }
  }

  static List<String> _parseVastXml(String xmlString) {
    final trackingUrls = <String>[];
    
    try {
      final document = XmlDocument.parse(xmlString);
      
      final impressions = document.findAllElements('Impression');
      for (var impression in impressions) {
        final url = impression.innerText.trim();
        if (url.isNotEmpty) trackingUrls.add(url);
      }
      
      final trackingEvents = document.findAllElements('Tracking');
      for (var tracking in trackingEvents) {
        final url = tracking.innerText.trim();
        if (url.isNotEmpty) trackingUrls.add(url);
      }
      
      final clickTracking = document.findAllElements('ClickTracking');
      for (var click in clickTracking) {
        final url = click.innerText.trim();
        if (url.isNotEmpty) trackingUrls.add(url);
      }
      
      final clickThrough = document.findAllElements('ClickThrough');
      for (var click in clickThrough) {
        final url = click.innerText.trim();
        if (url.isNotEmpty) trackingUrls.add(url);
      }
    } catch (e) {
      // Parse error, return empty list
    }
    
    return trackingUrls;
  }

  static Map<String, List<String>> parseVastXmlWithCategories(String xmlString) {
    final tracking = <String, List<String>>{
      'impressions': [],
      'clicks': [],
      'videoEvents': [],
    };
    
    try {
      final document = XmlDocument.parse(xmlString);
      
      final impressions = document.findAllElements('Impression');
      for (var impression in impressions) {
        final url = impression.innerText.trim();
        if (url.isNotEmpty) tracking['impressions']!.add(url);
      }
      
      final trackingEvents = document.findAllElements('Tracking');
      for (var trackingEvent in trackingEvents) {
        final eventType = trackingEvent.getAttribute('event') ?? 'unknown';
        final url = trackingEvent.innerText.trim();
        if (url.isNotEmpty) {
          tracking['videoEvents']!.add('[$eventType] $url');
        }
      }
      
      final clickTracking = document.findAllElements('ClickTracking');
      for (var click in clickTracking) {
        final url = click.innerText.trim();
        if (url.isNotEmpty) tracking['clicks']!.add(url);
      }
      
      final clickThrough = document.findAllElements('ClickThrough');
      for (var click in clickThrough) {
        final url = click.innerText.trim();
        if (url.isNotEmpty) tracking['clicks']!.add(url);
      }
    } catch (e) {
      // Parse error, return empty map
    }
    
    return tracking;
  }
}
