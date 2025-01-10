import 'package:flutter/material.dart';

class PlaceholderAdView extends StatelessWidget {
  final String placement;
  final String template;
  final String style;

  const PlaceholderAdView({
    super.key,
    required this.placement,
    required this.template,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.rectangle_outlined,
              size: 32,
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              placement,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              template,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'Courier',
                    color: Colors.grey,
                  ),
            ),
            Text(
              style,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'Courier',
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
