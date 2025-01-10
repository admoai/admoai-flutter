import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../../widgets/ad_layouts/horizontal_ad.dart';
import '../../../widgets/skeleton/skeleton_shape.dart';

class VehicleSelectionPreview extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const VehicleSelectionPreview({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Map background
        Container(
          color: Colors.grey[100],
        ),

        // Dark overlay
        Container(
          color: Colors.black.withAlpha(100),
        ),

        // Top buttons
        Padding(
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

        // Bottom sheet
        Column(
          children: [
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  // Sheet handle
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(77),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(
                    height: 400,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Search bar
                          const SkeletonShape(
                            type: SkeletonType.rectangle,
                            height: 36,
                            cornerRadius: 8,
                          ),
                          const SizedBox(height: 24),

                          // First two vehicle options
                          ...List.generate(
                            2,
                            (index) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildVehicleOption(),
                            ),
                          ),

                          // Ad placement
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child:
                                HorizontalAdView(creative: creative, sdk: sdk),
                          ),

                          // Last vehicle option
                          _buildVehicleOption(),
                        ],
                      ),
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

  Widget _buildVehicleOption() {
    return Row(
      children: [
        const SkeletonShape(
          type: SkeletonType.rectangle,
          width: 60,
          height: 60,
          cornerRadius: 8,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonShape(
                type: SkeletonType.text,
                width: 100,
                height: 16,
              ),
              SizedBox(height: 4),
              SkeletonShape(
                type: SkeletonType.text,
                width: 80,
                height: 14,
              ),
            ],
          ),
        ),
        const SkeletonShape(
          type: SkeletonType.rectangle,
          width: 60,
          height: 20,
          cornerRadius: 4,
        ),
      ],
    );
  }
}
