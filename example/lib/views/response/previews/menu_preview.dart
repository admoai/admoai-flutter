import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../../widgets/ad_layouts/text_only_ad.dart';
import '../../../widgets/skeleton/skeleton_shape.dart';

class MenuPreview extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const MenuPreview({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background
        Container(
          color: Colors.grey,
        ),

        // Semi-transparent overlay
        ColoredBox(
          color: Colors.black.withAlpha(77),
        ),

        // Menu drawer
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: MediaQuery.of(context).size.width * 0.85,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 8,
                    offset: const Offset(2, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // App logo
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: SkeletonShape(
                      type: SkeletonType.circle,
                      width: 60,
                      height: 60,
                    ),
                  ),

                  // Menu items
                  Expanded(
                    child: ListView.separated(
                      itemCount: 7,
                      separatorBuilder: (context, index) => const Divider(
                        indent: 60,
                      ),
                      itemBuilder: (context, index) => ListTile(
                        leading: const SkeletonShape(
                          type: SkeletonType.circle,
                          width: 24,
                          height: 24,
                        ),
                        title: const SkeletonShape(
                          type: SkeletonType.rectangle,
                          height: 16,
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: Colors.grey.withAlpha(77),
                        ),
                      ),
                    ),
                  ),

                  // Text-only ad
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextOnlyAdView(
                      creative: creative,
                      sdk: sdk,
                    ),
                  ),

                  // Bottom profile section
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const SkeletonShape(
                          type: SkeletonType.circle,
                          width: 40,
                          height: 40,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SkeletonShape(
                              type: SkeletonType.rectangle,
                              width: 120,
                              height: 16,
                            ),
                            const SizedBox(height: 4),
                            const SkeletonShape(
                              type: SkeletonType.rectangle,
                              width: 80,
                              height: 14,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
