import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../../widgets/ad_layouts/horizontal_with_companion_ad.dart';

class HomePreview extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const HomePreview({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background
        ColoredBox(
          color: Colors.grey.withAlpha(51),
          child: const SizedBox.expand(),
        ),

        // Ad card
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 70, 16, 0),
                child: HorizontalWithCompanionAd(
                  creative: creative,
                  onCompanionOpen: () {},
                  onImpression: (_) {},
                  onAdClick: (_) {},
                ),
              ),
              const Spacer(),
            ],
          ),
        ),

        // Floating buttons
        Positioned(
          right: 24,
          bottom: 100,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                      color: Colors.black.withAlpha(64),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                      color: Colors.black.withAlpha(64),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom navigation dots
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                  color: Colors.black.withAlpha(32),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) {
                return Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color:
                        index == 1 ? Colors.black : Colors.grey.withAlpha(51),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ),

        // Top buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
