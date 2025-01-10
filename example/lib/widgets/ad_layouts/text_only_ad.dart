import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class TextOnlyAdView extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const TextOnlyAdView({
    super.key,
    required this.creative,
    required this.sdk,
  });

  String? get text => creative.contents
      .firstWhere((c) => c.key == 'text',
          orElse: () => Content(key: 'text', value: null, type: ''))
      .value;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text!,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Advertiser info
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                creative.advertiser.logoUrl,
                width: 16,
                height: 16,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.business, size: 16),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              creative.advertiser.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Sponsored',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
