# AdMoai Flutter SDK — example

The smallest complete integration: initialize the SDK, request an ad for a placement, read
its content and report the impression. The [README](https://github.com/admoai/admoai-flutter#readme)
covers every feature (video, Journey Ads, Sponsored Pins, targeting, tracking).

```dart
import 'package:admoai/admoai.dart';

Future<void> main() async {
  // 1. Initialize the SDK once, at app start.
  final sdk = await AdMoai.initialize(
    config: SDKConfig(baseUrl: 'https://api.admoai.com', apiVersion: '2025-11-01'),
  );

  // 2. Optional: who the user is, and their consent.
  sdk.setUserConfig(id: 'user_123', timezone: 'UTC', consent: Consent(gdpr: true));

  // 3. Ask for ads on your placements.
  final request = sdk.createRequestBuilder().addPlacement(key: 'home').build();
  final response = await sdk.requestAds(request);

  // 4. Render each creative from its content fields, and track what happens.
  for (final decision in response.body.data ?? const []) {
    for (final creative in decision.creatives ?? const []) {
      final headline = creative.contents.getContent('headline')?.value;
      print('${decision.placement}: $headline');

      sdk.fireImpression(creative.tracking); // when it is shown
      // sdk.fireClick(creative.tracking);   // when the user taps it
    }
  }
}
```

The full sample app that used to live here was retired on 2026-10-21; its last version is kept
under the git tag `sample-app-archive` of this repository.
