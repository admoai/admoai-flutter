import 'dart:convert';

import 'package:admoai/admoai.dart';
import 'package:flutter/material.dart';

/// Override with `--dart-define=ADMOAI_BASE_URL=...`. The default reaches a
/// decision engine running on the host machine from an Android emulator.
const String baseUrl = String.fromEnvironment(
  'ADMOAI_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = await AdMoai.initialize(
    config: SDKConfig(baseUrl: baseUrl, apiVersion: '2025-11-01'),
  );
  runApp(ExampleApp(sdk: sdk));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.sdk});

  final AdMoai sdk;

  @override
  Widget build(BuildContext context) {
    final request = (sdk.createRequestBuilder()
          ..addPlacement(key: 'home')
          ..setAgeGroup(AgeGroup.age25To34)
          ..setTripFrequency30d(TripFrequency30d.zero)
          ..setPublisherSegments(['airport_commuter', 'high_value']))
        .build();
    final json = const JsonEncoder.withIndent('  ').convert(request.toJson());
    final device = sdk.deviceConfig;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('AdMoai example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Base URL: $baseUrl'),
            Text(
              'carrier: ${device.carrier ?? '-'}',
              key: const Key('device-carrier'),
            ),
            Text(
              'category: ${device.category?.value ?? '-'}',
              key: const Key('device-category'),
            ),
            const SizedBox(height: 16),
            SelectableText(json, key: const Key('request-json')),
          ],
        ),
      ),
    );
  }
}
