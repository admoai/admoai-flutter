import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden request bodies captured from `main` before audience signals existed.
/// When nothing new is set the wire JSON must stay byte-for-byte identical.
DecisionRequestBuilder _builder() {
  return DecisionRequestBuilder(
    appConfig: AppConfig(
      name: 'Demo',
      version: '1.2.3',
      buildNumber: '45',
      identifier: 'com.example.demo',
      language: 'en',
    ),
    deviceConfig: DeviceConfig(
      id: 'dev-1',
      model: 'Pixel 9',
      manufacturer: 'Google',
      os: 'android',
      osVersion: '15',
      timezone: 'Europe/Madrid',
      language: 'es',
    ),
    userConfig: UserConfig(id: 'user-1', ip: '203.0.113.7', timezone: 'UTC'),
  )..addPlacement(key: 'home', count: 2);
}

void main() {
  test('full request with generic custom targeting is unchanged', () {
    final request = _builder()
        .addCustomTargeting(key: 'tier', value: 'gold')
        .addCustomTargeting(key: 'tags', value: ['a', 'b']).build();
    expect(jsonEncode(request.toJson()), _fullGolden);
  });

  test('request without targeting is unchanged', () {
    expect(jsonEncode(_builder().build().toJson()), _plainGolden);
  });

  test('disableDeviceCollection omits the whole device', () {
    final request = _builder().disableDeviceCollection().build();
    expect(jsonEncode(request.toJson()), _noDeviceGolden);
  });
}

const _fullGolden =
    r'''{"placements":[{"key":"home","count":2}],"targeting":{"custom":[{"key":"tier","value":"gold"},{"key":"tags","value":["a","b"]}]},"user":{"id":"user-1","ip":"203.0.113.7","timezone":"UTC","consent":{"gdpr":false}},"device":{"id":"dev-1","model":"Pixel 9","manufacturer":"Google","os":"android","osVersion":"15","timezone":"Europe/Madrid","language":"es"},"app":{"name":"Demo","version":"1.2.3","buildNumber":"45","identifier":"com.example.demo","language":"en"}}''';
const _plainGolden =
    r'''{"placements":[{"key":"home","count":2}],"user":{"id":"user-1","ip":"203.0.113.7","timezone":"UTC","consent":{"gdpr":false}},"device":{"id":"dev-1","model":"Pixel 9","manufacturer":"Google","os":"android","osVersion":"15","timezone":"Europe/Madrid","language":"es"},"app":{"name":"Demo","version":"1.2.3","buildNumber":"45","identifier":"com.example.demo","language":"en"}}''';
const _noDeviceGolden =
    r'''{"placements":[{"key":"home","count":2}],"user":{"id":"user-1","ip":"203.0.113.7","timezone":"UTC","consent":{"gdpr":false}},"app":{"name":"Demo","version":"1.2.3","buildNumber":"45","identifier":"com.example.demo","language":"en"}}''';
