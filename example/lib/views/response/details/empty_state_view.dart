import 'package:flutter/material.dart';
import '../response_details_view.dart';

class EmptyStateView extends StatelessWidget {
  final DataTab tab;

  const EmptyStateView({super.key, required this.tab});

  String get _message {
    switch (tab) {
      case DataTab.contents:
        return 'No content data available';
      case DataTab.info:
        return 'No creative information available';
      case DataTab.tracking:
        return 'No tracking data available';
      case DataTab.validation:
        return 'No validation data available';
      case DataTab.json:
        return 'No JSON data available';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            _message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
        ],
      ),
    );
  }
}
