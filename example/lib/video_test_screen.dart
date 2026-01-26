import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import 'package:http/http.dart' as http;
import 'vast_parser.dart';

class VideoTestScreen extends StatefulWidget {
  const VideoTestScreen({super.key});

  @override
  State<VideoTestScreen> createState() => _VideoTestScreenState();
}

class _VideoTestScreenState extends State<VideoTestScreen> {
  late AdMoai sdk;
  String output = 'Initializing...';
  bool loading = false;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    _initSDK();
  }

  Future<void> _initSDK() async {
    try {
      final config = SDKConfig(
        baseUrl: 'https://api.acme.admoai.com',
        apiVersion: '2025-11-01',
      );
      sdk = await AdMoai.initialize(config: config);
      setState(() {
        initialized = true;
        output = 'SDK initialized\n\nEndpoint: https://api.acme.admoai.com\nAPI Version: 2025-11-01\n\nTap "Test Video Ads" to make request.';
      });
    } catch (e) {
      setState(() {
        output = 'SDK initialization failed: $e';
      });
    }
  }

  Future<void> _testVideoAds() async {
    setState(() {
      loading = true;
      output = 'Making request to api.acme.admoai.com...\nPlacement: map\n\n';
    });

    try {
      // Create minimal request matching the curl example
      final builder = sdk.createRequestBuilder();
      builder.disableAppCollection();
      builder.disableDeviceCollection();
      builder.clearUser();
      final request = builder.addPlacement(key: 'map').build();

      final httpRequest = sdk.getHttpRequest(request);
      
      String result = 'REQUEST:\n';
      result += 'URL: ${sdk.config.baseUrl}${httpRequest.path}\n\n';
      result += 'Headers:\n';
      httpRequest.headers?.forEach((key, value) {
        result += '  $key: $value\n';
      });
      result += '\nBody:\n${httpRequest.body}\n\n';
      
      setState(() {
        output = result + 'Sending request...\n';
      });

      final response = await sdk.requestAds(request);
      
      result += 'RESPONSE:\n';
      result += 'Status: ${response.response.statusCode}\n';
      result += 'Success: ${response.body.success}\n\n';

      final decisions = response.body.data;
      if (decisions == null || decisions.isEmpty) {
        result += 'No decisions returned.\n';
        setState(() {
          output = result;
          loading = false;
        });
        return;
      }

      result += 'Decisions: ${decisions.length}\n\n';

      for (var i = 0; i < decisions.length; i++) {
        final decision = decisions[i];
        result += 'DECISION ${i + 1}: ${decision.placement}\n';

        if (decision.creatives == null || decision.creatives!.isEmpty) {
          result += '  No creatives\n';
          continue;
        }

        for (var j = 0; j < decision.creatives!.length; j++) {
          final creative = decision.creatives![j];
          result += '\nCreative ${j + 1}:\n';
          result += '  Advertiser: ${creative.advertiser.name}\n';
          result += '  Template: ${creative.template.key}\n';
          result += '  Delivery: ${creative.delivery ?? "native"}\n';

          if (creative.vast != null) {
            result += '\nVAST Data:\n';
            if (creative.vast!.tagUrl != null) {
              final url = creative.getVastTagUrl();
              result += '  Tag URL: ${url?.substring(0, 60)}...\n';
            }
            if (creative.vast!.xmlBase64 != null) {
              result += '  XML Base64: ${creative.vast!.xmlBase64!.length} chars\n';
            }
          }

          if (creative.isSkippable()) {
            result += '\nSkippable: ${creative.getSkipOffset()}\n';
          }

          result += '\nTracking:\n';
          
          setState(() {
            output = result + 'Processing tracking...\n';
          });
          
          if (creative.isVastTagDelivery() && creative.vast?.tagUrl != null) {
            result += '  Method: VAST TAG\n';
            
            final vastTagUrl = creative.getVastTagUrl();
            if (vastTagUrl != null) {
              try {
                final vastTracking = await VastParser.parseVastXmlWithCategories(
                  await http.read(Uri.parse(vastTagUrl))
                );
                
                result += '  Impressions: ${vastTracking['impressions']!.length}\n';
                result += '  Clicks: ${vastTracking['clicks']!.length}\n';
                result += '  Video Events: ${vastTracking['videoEvents']!.length}\n';
                
                for (var url in vastTracking['impressions']!) {
                  sdk.fireTracking(url);
                }
                
                for (var eventUrl in vastTracking['videoEvents']!) {
                  final url = eventUrl.split('] ').last;
                  sdk.fireTracking(url);
                }
                
                result += '  Fired tracking\n';
              } catch (e) {
                result += '  Error: $e\n';
              }
            }
            
          } else if (creative.isVastXmlDelivery() && creative.vast?.xmlBase64 != null) {
            result += '  Method: VAST XML\n';
            
            final xmlBase64 = creative.getVastXmlBase64();
            if (xmlBase64 != null) {
              try {
                final vastTracking = VastParser.parseVastXmlBase64(xmlBase64);
                result += '  Tracking URLs: ${vastTracking.length}\n';
                
                for (var url in vastTracking) {
                  sdk.fireTracking(url);
                }
                result += '  Fired tracking\n';
              } catch (e) {
                result += '  Error: $e\n';
              }
            }
            
          } else if (creative.isJsonDelivery()) {
            result += '  Method: JSON\n';
            
            final tracking = creative.tracking;
            int totalFired = 0;
            
            if (tracking.impressions.isNotEmpty) {
              for (var imp in tracking.impressions) {
                sdk.fireImpression(tracking, key: imp.key);
                totalFired++;
              }
            }
            
            if (tracking.clicks != null && tracking.clicks!.isNotEmpty) {
              for (var click in tracking.clicks!) {
                sdk.fireClick(tracking, key: click.key);
                totalFired++;
              }
            }
            
            if (tracking.videoEvents != null && tracking.videoEvents!.isNotEmpty) {
              for (var event in tracking.videoEvents!) {
                sdk.fireVideoEvent(tracking, event.key);
                totalFired++;
              }
            }
            
            result += '  Fired $totalFired tracking beacons\n';
          } else {
            result += '  No tracking data\n';
          }

          result += '\nContent: ${creative.contents.length} fields\n';
        }
      }

      result += '\nTest complete. Check dashboard for tracking.';

      setState(() {
        output = result;
        loading = false;
      });
    } catch (e) {
      setState(() {
        output = 'Error: $e';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Ads Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Video Ads SDK Test',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This test makes a real request to api.acme.admoai.com and tests all Video Ads methods.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: (loading || !initialized) ? null : _testVideoAds,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(loading ? 'Testing...' : 'Test Video Ads'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  output,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (initialized) {
      sdk.dispose();
    }
    super.dispose();
  }
}
