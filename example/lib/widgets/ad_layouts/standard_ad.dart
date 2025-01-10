import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class StandardAdView extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const StandardAdView({
    super.key,
    required this.creative,
    required this.sdk,
  });

  String get coverImage =>
      creative.contents.firstWhere((c) => c.key == 'coverImage').value ?? '';

  String get headline =>
      creative.contents.firstWhere((c) => c.key == 'headline').value ?? '';

  String get bodyText =>
      creative.contents.firstWhere((c) => c.key == 'body').value ?? '';

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: AspectRatio(
              aspectRatio: 1.91,
              child: Image.network(
                coverImage,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.withAlpha(20),
                  child: const Icon(Icons.photo, color: Colors.grey),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Headline
                Text(
                  headline,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Body
                Text(
                  bodyText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 16),

                // Advertiser info and Ad badge
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        creative.advertiser.logoUrl,
                        width: 16,
                        height: 16,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                          Icons.business,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      creative.advertiser.name,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Ad',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.surface,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
