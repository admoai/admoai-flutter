import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class HTTPRequestView extends StatelessWidget {
  final HTTPRequest request;

  const HTTPRequestView({
    super.key,
    required this.request,
  });

  String? get formattedBody {
    if (request.body == null) return null;
    try {
      final json = jsonDecode(request.body!);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (e) {
      return null;
    }
  }

  // Add a constant for monospace style
  static TextStyle monoStyle(BuildContext context) => TextStyle(
        fontFamily: Theme.of(context).platform == TargetPlatform.iOS
            ? 'Menlo'
            : 'Roboto Mono',
        fontSize: 13,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTP Request'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Request Section
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'REQUEST',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(
                    'Method',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    request.method.name.toUpperCase(),
                    style: monoStyle(context),
                  ),
                ),
                ListTile(
                  title: Text(
                    'Path',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    request.path,
                    style: monoStyle(context),
                  ),
                ),
              ],
            ),
          ),

          // Headers Section
          if (request.headers?.isNotEmpty ?? false)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'HEADERS',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                    ),
                  ),
                  const Divider(height: 1),
                  ...Map.fromEntries(
                    request.headers!.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key)),
                  ).entries.map(
                        (header) => ListTile(
                          title: Text(
                            header.key,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          subtitle: Text(
                            header.value,
                            style: monoStyle(context),
                          ),
                        ),
                      ),
                ],
              ),
            ),

          // Body Section
          if (formattedBody != null)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'BODY',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                    ),
                  ),
                  const Divider(height: 1),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      formattedBody!,
                      style: monoStyle(context).copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
