import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class TrackingTabView extends StatelessWidget {
  final Creative creative;
  final AdMoai sdk;

  const TrackingTabView({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (creative.tracking.impressions.isNotEmpty) ...[
          Text(
            'Impressions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...creative.tracking.impressions.map((t) => TrackingItemView(
                trackingKey: t.key,
                url: t.url,
                sdk: sdk,
              )),
        ],
        if (creative.tracking.clicks?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text(
            'Clicks',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...creative.tracking.clicks!.map((t) => TrackingItemView(
                trackingKey: t.key,
                url: t.url,
                sdk: sdk,
              )),
        ],
        if (creative.tracking.custom?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text(
            'Custom',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ...creative.tracking.custom!.map((t) => TrackingItemView(
                trackingKey: t.key,
                url: t.url,
                sdk: sdk,
              )),
        ],
      ],
    );
  }
}

class TrackingItemView extends StatefulWidget {
  final String trackingKey;
  final String url;
  final AdMoai sdk;

  const TrackingItemView({
    super.key,
    required this.trackingKey,
    required this.url,
    required this.sdk,
  });

  @override
  State<TrackingItemView> createState() => _TrackingItemViewState();
}

class _TrackingItemViewState extends State<TrackingItemView> {
  TrackingButtonState _buttonState = TrackingButtonState.ready;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.trackingKey,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'Courier',
                        ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _buttonState == TrackingButtonState.loading
                      ? null
                      : _fireTracking,
                  icon: _buildStatusIcon(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.url,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontFamily: 'Courier'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (_buttonState) {
      case TrackingButtonState.loading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case TrackingButtonState.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case TrackingButtonState.error:
        return const Icon(Icons.error, color: Colors.red);
      case TrackingButtonState.ready:
        return const Icon(Icons.play_circle_filled);
    }
  }

  Future<void> _fireTracking() async {
    setState(() => _buttonState = TrackingButtonState.loading);

    try {
      widget.sdk.fireTracking(widget.url);
      setState(() => _buttonState = TrackingButtonState.success);

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() => _buttonState = TrackingButtonState.ready);
        }
      });
    } catch (e) {
      setState(() => _buttonState = TrackingButtonState.error);
    }
  }
}

enum TrackingButtonState {
  ready,
  loading,
  success,
  error,
}
