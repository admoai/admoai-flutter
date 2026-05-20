import 'package:flutter_test/flutter_test.dart';
import 'package:admoai/admoai.dart';

Map<String, dynamic> _baseCreativeJson({
  List<Map<String, dynamic>>? resources,
}) {
  return {
    'contents': [
      {'key': 'headline', 'value': 'hi', 'type': 'text'}
    ],
    'advertiser': {
      'name': 'ACME',
      'legalName': 'ACME Ltd',
      'logoUrl': 'https://example.com/logo.png'
    },
    'template': {'key': 'wide', 'style': 'imageLeft'},
    'tracking': {
      'impressions': [
        {'key': 'default', 'url': 'https://example.com/imp'}
      ]
    },
    if (resources != null) 'verificationScriptResources': resources,
  };
}

void main() {
  group('OM verification parsing', () {
    test('parses two VerificationScriptResource entries', () {
      final creative = Creative.fromJson(_baseCreativeJson(resources: [
        {
          'vendorKey': 'ias',
          'scriptUrl': 'https://cdn.ias.com/x.js',
          'verificationParameters': 'p=1',
        },
        {
          'vendorKey': 'doubleverify',
          'scriptUrl': 'https://cdn.dv.com/x.js',
          'verificationParameters': null,
        },
      ]));

      expect(creative.verificationScriptResources, isNotNull);
      expect(creative.verificationScriptResources!.length, equals(2));
      expect(creative.verificationScriptResources!.first.vendorKey,
          equals('ias'));
      expect(creative.verificationScriptResources!.first.scriptUrl,
          equals('https://cdn.ias.com/x.js'));
      expect(creative.verificationScriptResources!.first.verificationParameters,
          equals('p=1'));
      expect(creative.verificationScriptResources!.last.verificationParameters,
          isNull);
    });

    test('verificationScriptResources is null when absent', () {
      final creative = Creative.fromJson(_baseCreativeJson());
      expect(creative.verificationScriptResources, isNull);
    });
  });

  group('OMHelper extension', () {
    test('getVerificationResources returns the list when present', () {
      final creative = Creative.fromJson(_baseCreativeJson(resources: [
        {
          'vendorKey': 'ias',
          'scriptUrl': 'https://cdn.ias.com/x.js',
          'verificationParameters': 'p=1',
        }
      ]));

      final resources = creative.getVerificationResources();
      expect(resources, isNotNull);
      expect(resources!.length, equals(1));
      expect(resources.first.vendorKey, equals('ias'));
    });

    test('getVerificationResources returns null when absent', () {
      final creative = Creative.fromJson(_baseCreativeJson());
      expect(creative.getVerificationResources(), isNull);
    });

    test('hasOMVerification returns true when at least one resource exists',
        () {
      final creative = Creative.fromJson(_baseCreativeJson(resources: [
        {
          'vendorKey': 'ias',
          'scriptUrl': 'https://cdn.ias.com/x.js',
          'verificationParameters': null,
        }
      ]));
      expect(creative.hasOMVerification(), isTrue);
    });

    test('hasOMVerification returns false when null', () {
      final creative = Creative.fromJson(_baseCreativeJson());
      expect(creative.hasOMVerification(), isFalse);
    });

    test('hasOMVerification returns false when empty list', () {
      final creative = Creative.fromJson(_baseCreativeJson(resources: []));
      expect(creative.hasOMVerification(), isFalse);
    });
  });
}
