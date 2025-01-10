import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../../widgets/ad_layouts/carousel_ad.dart';
import '../../../widgets/skeleton/skeleton_shape.dart';

class PromotionsPreview extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const PromotionsPreview({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Categories row
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  6,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SkeletonShape(
                      type: SkeletonType.rectangle,
                      width: 80,
                      height: 32,
                      cornerRadius: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Carousel without padding
          CarouselAdView(creative: creative, sdk: sdk),
          const SizedBox(height: 32),

          // Product grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: 5,
              itemBuilder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: const SkeletonShape(
                      type: SkeletonType.rectangle,
                      cornerRadius: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SkeletonShape(
                    type: SkeletonType.rectangle,
                    height: 12,
                    cornerRadius: 4,
                  ),
                  const SizedBox(height: 4),
                  const SkeletonShape(
                    type: SkeletonType.rectangle,
                    width: 80,
                    height: 12,
                    cornerRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
