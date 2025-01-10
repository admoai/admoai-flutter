import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../../widgets/ad_layouts/standard_ad.dart';
import '../../../widgets/skeleton/skeleton_shape.dart';

class RideSummaryPreview extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const RideSummaryPreview({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Top section with addresses and map
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Addresses on the left
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonShape(
                        type: SkeletonType.rectangle,
                        width: 120,
                        height: 16,
                        cornerRadius: 4,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SkeletonShape(
                            type: SkeletonType.circle,
                            width: 20,
                            height: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                SkeletonShape(
                                  type: SkeletonType.text,
                                  height: 14,
                                ),
                                SizedBox(height: 4),
                                SkeletonShape(
                                  type: SkeletonType.text,
                                  width: 100,
                                  height: 14,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SkeletonShape(
                            type: SkeletonType.circle,
                            width: 20,
                            height: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                SkeletonShape(
                                  type: SkeletonType.text,
                                  height: 14,
                                ),
                                SizedBox(height: 4),
                                SkeletonShape(
                                  type: SkeletonType.text,
                                  width: 100,
                                  height: 14,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Map placeholder
                const SkeletonShape(
                  type: SkeletonType.rectangle,
                  width: 120,
                  height: 120,
                  cornerRadius: 8,
                ),
              ],
            ),
          ),

          const Divider(),

          // Ride information
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(
                      4,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SkeletonShape(
                          type: SkeletonType.text,
                          width: 160 - index * 10,
                          height: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      4,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SkeletonShape(
                          type: SkeletonType.text,
                          width: 100 - index * 10,
                          height: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Ad placement
          Padding(
            padding: const EdgeInsets.all(16),
            child: StandardAdView(creative: creative, sdk: sdk),
          ),

          const Divider(),

          // Text lines after ad
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonShape(
                  type: SkeletonType.text,
                  lines: 3,
                  height: 14,
                  spacing: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
