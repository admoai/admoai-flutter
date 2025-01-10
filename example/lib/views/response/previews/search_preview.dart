import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../../widgets/ad_layouts/horizontal_ad.dart';
import '../../../widgets/skeleton/skeleton_shape.dart';

class SearchPreview extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const SearchPreview({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar placeholder
        const Padding(
          padding: EdgeInsets.all(16),
          child: SkeletonShape(
            type: SkeletonType.rectangle,
            height: 44,
            cornerRadius: 8,
          ),
        ),

        // Text blocks before ad
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SkeletonShape(
            type: SkeletonType.text,
            lines: 3,
            spacing: 12,
          ),
        ),

        const SizedBox(height: 16),

        // Horizontal ad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: HorizontalAdView(creative: creative, sdk: sdk),
        ),

        const SizedBox(height: 16),

        // Text blocks after ad
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SkeletonShape(
                type: SkeletonType.text,
                lines: 4,
                spacing: 12,
              ),
              SizedBox(height: 16),
              SkeletonShape(
                type: SkeletonType.text,
                lines: 5,
                spacing: 12,
              ),
              SizedBox(height: 16),
              SkeletonShape(
                type: SkeletonType.text,
                lines: 3,
                spacing: 12,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
