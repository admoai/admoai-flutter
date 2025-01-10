import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'mock_data.dart';
import 'views/request/timezone_picker.dart';
import 'views/request/http_request_view.dart';
import 'views/request/geo_targeting_picker.dart';
import 'views/request/location_targeting_picker.dart';
import 'views/request/custom_targeting_picker.dart';
import 'views/response/preview_result_view.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdMoai Demo',
      theme: ThemeData(useMaterial3: true),
      home: const DecisionRequestForm(),
    );
  }
}

class DecisionRequestForm extends StatefulWidget {
  const DecisionRequestForm({super.key});

  @override
  State<DecisionRequestForm> createState() => _DecisionRequestFormState();
}

class _DecisionRequestFormState extends State<DecisionRequestForm> {
  late AdMoai sdk;
  String placementKey = 'home';
  bool collectAppData = true;
  bool collectDeviceData = true;
  AppDetails? appDetails;
  DeviceDetails? deviceDetails;
  Targeting targeting = Targeting();
  User user = User(
    id: 'user_123',
    ip: '203.0.113.1',
    timezone: null,
    consent: Consent(gdpr: true),
  );

  @override
  void initState() {
    super.initState();
    _initializeSDK();
    _loadAppDetails();
    _loadDeviceDetails();
    _loadUserTimezone();
  }

  Future<void> _initializeSDK() async {
    final config = SDKConfig(baseUrl: 'https://mock.api.admoai.com');
    sdk = await AdMoai.initialize(config: config);
  }

  Future<void> _loadAppDetails() async {
    final details = await getAppDetails();
    setState(() {
      appDetails = details;
    });
  }

  Future<void> _loadDeviceDetails() async {
    final details = await getDeviceDetails();
    setState(() {
      deviceDetails = details;
    });
  }

  Future<void> _loadUserTimezone() async {
    final deviceTimezone = await FlutterTimezone.getLocalTimezone();
    setState(() {
      user = User(
        id: user.id,
        ip: user.ip,
        timezone: deviceTimezone,
        consent: user.consent,
      );
    });
  }

  void _showPlacementPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select Placement',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: placementMockData.length,
              itemBuilder: (context, index) {
                final placement = placementMockData[index];
                return ListTile(
                  leading: Icon(
                    placement.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(placement.name),
                  trailing: placementKey == placement.id
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      placementKey = placement.id;
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  DecisionRequest buildRequest() {
    final builder = sdk
        .createRequestBuilder()
        .addPlacement(key: placementKey)
        .setGeoTargeting(targeting.geo)
        .setLocationTargeting(targeting.location ?? [])
        .setCustomTargeting(targeting.custom ?? [])
        .setUserIp(user.ip)
        .setUserId(user.id)
        .setUserTimezone(user.timezone)
        .setUserConsent(user.consent);

    if (!collectAppData) {
      builder.disableAppCollection();
    }

    if (!collectDeviceData) {
      builder.disableDeviceCollection();
    }

    return builder.build();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Decision Request'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'This interface demonstrates how to build a decision request. The actual implementation will be handled by the SDK.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Placement Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(
                    'Placement',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Key'),
                  trailing: Text(
                    placementMockData
                        .firstWhere((p) => p.id == placementKey)
                        .name,
                    style: TextStyle(fontSize: 16),
                  ),
                  onTap: _showPlacementPicker,
                ),
                const ListTile(
                  leading: Icon(Icons.layers),
                  title: Text('Format'),
                  trailing: Text(
                    'Native',
                    style: TextStyle(fontSize: 16),
                  ),
                  enabled: false,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'This demo uses a single placement object, but you can include multiple ones. For each, you can specify the number of creatives to return and filter by advertiser and template.\nCurrently, AdMoai supports only the native format.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Targeting Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(
                    'Targeting',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('Geo Targeting'),
                  trailing: Text(
                    targeting.geo?.isEmpty ?? true
                        ? 'None'
                        : '${targeting.geo?.length} cities',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GeoTargetingPicker(
                          targeting: targeting,
                          onChanged: (newTargeting) {
                            setState(() {
                              targeting = newTargeting;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Location Targeting'),
                  trailing: Text(
                    targeting.location?.isEmpty ?? true
                        ? 'None'
                        : '${targeting.location?.length} locations',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LocationTargetingPicker(
                          targeting: targeting,
                          onChanged: (newTargeting) {
                            setState(() {
                              targeting = newTargeting;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Custom Targeting'),
                  trailing: Text(
                    targeting.custom?.isEmpty ?? true
                        ? 'None'
                        : '${targeting.custom?.length} targets',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomTargetingPicker(
                          targeting: targeting,
                          onChanged: (newTargeting) {
                            setState(() {
                              targeting = newTargeting;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Targeting allows you to specify criteria to filter the creatives returned by AdMoai.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // User Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(
                    'User',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('ID'),
                  trailing: SizedBox(
                    width: 150,
                    child: TextField(
                      textAlign: TextAlign.end,
                      controller: TextEditingController(text: user.id),
                      decoration: const InputDecoration(
                        hintText: 'User ID',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        setState(() {
                          user = User(
                            id: value,
                            ip: user.ip,
                            timezone: user.timezone,
                            consent: user.consent,
                          );
                        });
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.network_wifi),
                  title: const Text('IP'),
                  trailing: SizedBox(
                    width: 150,
                    child: TextField(
                      textAlign: TextAlign.end,
                      controller: TextEditingController(text: user.ip),
                      decoration: const InputDecoration(
                        hintText: 'IP Address',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        setState(() {
                          user = User(
                            id: user.id,
                            ip: value,
                            timezone: user.timezone,
                            consent: user.consent,
                          );
                        });
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Timezone'),
                  trailing: Text(
                    user.timezone ?? 'None',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TimezonePicker(
                          selectedTimezone: user.timezone,
                          onChanged: (timezone) {
                            setState(() {
                              user = User(
                                id: user.id,
                                ip: user.ip,
                                timezone: timezone,
                                consent: user.consent,
                              );
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
                ExpansionTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Consent'),
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user),
                      title: const Text('GDPR'),
                      value: user.consent?.gdpr ?? false,
                      onChanged: (value) {
                        setState(() {
                          user = User(
                            id: user.id,
                            ip: user.ip,
                            timezone: user.timezone,
                            consent: Consent(gdpr: value),
                          );
                        });
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'The user ID and IP address enable frequency capping and geo-targeting respectively. The timezone enables day/hour parting for time-based ad delivery. GDPR consent must be enabled to serve ads with frequency capping.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Data Collection Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(
                    'Data Collection',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Collect App Data'),
                  value: collectAppData,
                  onChanged: (value) => setState(() => collectAppData = value),
                ),
                SwitchListTile(
                  title: const Text('Collect Device Data'),
                  value: collectDeviceData,
                  onChanged: (value) =>
                      setState(() => collectDeviceData = value),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'App and device information are collected by default when initializing the SDK. You can disable collection either globally using SDK configuration or per-request.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // App Info Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(
                    'App',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Name'),
                  trailing: Text(appDetails?.name ?? '-'),
                ),
                ListTile(
                  title: const Text('Version'),
                  trailing: Text(appDetails?.version ?? '-'),
                ),
                ListTile(
                  title: const Text('Build'),
                  trailing: Text(appDetails?.buildNumber ?? '-'),
                ),
                ListTile(
                  title: const Text('Identifier'),
                  trailing: Text(appDetails?.identifier ?? '-'),
                ),
                ListTile(
                  title: const Text('Language'),
                  trailing: Text(appDetails?.language ?? '-'),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'App information is automatically set by the SDK.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Device Info Section
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(
                    'Device',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Device ID'),
                  trailing: Text(deviceDetails?.id ?? '-'),
                ),
                ListTile(
                  title: const Text('Model'),
                  trailing: Text(deviceDetails?.model ?? '-'),
                ),
                ListTile(
                  title: const Text('Manufacturer'),
                  trailing: Text(deviceDetails?.manufacturer ?? '-'),
                ),
                ListTile(
                  title: const Text('OS'),
                  trailing: Text(deviceDetails?.os ?? '-'),
                ),
                ListTile(
                  title: const Text('OS Version'),
                  trailing: Text(deviceDetails?.osVersion ?? '-'),
                ),
                ListTile(
                  title: const Text('Timezone'),
                  trailing: Text(deviceDetails?.timezone ?? '-'),
                ),
                ListTile(
                  title: const Text('Language'),
                  trailing: Text(deviceDetails?.language ?? '-'),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Device information is automatically set by the SDK.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  try {
                    final request = sdk.getHttpRequest(buildRequest());
                    if (!mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HTTPRequestView(request: request),
                      ),
                    );
                  } catch (e) {
                    // Handle error
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.code),
                    SizedBox(width: 8),
                    Text('View HTTP Request'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  try {
                    final request = buildRequest();
                    // print('Request: ${request.toJson()}'); // Debug request

                    final response = await sdk.requestAds(request);
                    // print('Response: $response'); // Debug response

                    if (!mounted) return;

                    final creative = response.body.data?.first.creatives?.first;
                    if (creative == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No ads available')),
                      );
                      return;
                    }

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PreviewResultView(
                          creative: creative,
                          placement: placementKey,
                          rawResponse: response.rawBody ?? '',
                          requestBuilder: buildRequest,
                          sdk: sdk,
                        ),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e is ClientError
                              ? 'Client Error: ${e.message}'
                              : 'Error: ${e.toString()}',
                        ),
                      ),
                    );
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_forward_rounded),
                    SizedBox(width: 8),
                    Text('Request and Preview'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
