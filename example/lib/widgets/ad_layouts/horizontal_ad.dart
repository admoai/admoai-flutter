import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class HorizontalAdView extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const HorizontalAdView({
    super.key,
    required this.creative,
    required this.sdk,
  });

  bool get isImageRight => creative.template.style == 'imageRight';
  bool get isImageOnly => creative.template.style == 'wideImageOnly';

  String? get wideImage => creative.contents
      .firstWhere((c) => c.key == 'wideImage',
          orElse: () => Content(key: 'wideImage', value: null, type: ''))
      .value;

  String? get squareImage => creative.contents
      .firstWhere((c) => c.key == 'squareImage',
          orElse: () => Content(key: 'squareImage', value: null, type: ''))
      .value;

  String? get headline => creative.contents
      .firstWhere((c) => c.key == 'headline',
          orElse: () => Content(key: 'headline', value: null, type: ''))
      .value;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4, // 4:1 ratio
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: isImageOnly
            ? _buildImageOnlyLayout(context)
            : _buildStandardLayout(context),
      ),
    );
  }

  Widget _buildImageOnlyLayout(BuildContext context) {
    return Stack(
      children: [
        // Wide image
        Image.network(
          wideImage ?? '',
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey.withAlpha(20),
            child: const Icon(Icons.photo, color: Colors.grey),
          ),
        ),

        // Gradient overlay
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withAlpha(128),
                  Colors.black.withAlpha(0),
                ],
              ),
            ),
            child: _buildAdvertiserInfo(context, isOverlay: true),
          ),
        ),
      ],
    );
  }

  Widget _buildStandardLayout(BuildContext context) {
    return Row(
      children: [
        if (!isImageRight) _buildSquareImage(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (headline != null) ...[
                  Text(
                    headline!,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                ],
                _buildAdvertiserInfo(context),
              ],
            ),
          ),
        ),
        if (isImageRight) _buildSquareImage(),
      ],
    );
  }

  Widget _buildSquareImage() {
    return AspectRatio(
      aspectRatio: 1,
      child: Image.network(
        squareImage ?? '',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey.withAlpha(20),
          child: const Icon(Icons.photo, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildAdvertiserInfo(BuildContext context, {bool isOverlay = false}) {
    return Row(
      children: [
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
        const SizedBox(width: 8),
        Text(
          creative.advertiser.name,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isOverlay ? Colors.white : null,
              ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
    );
  }
}
