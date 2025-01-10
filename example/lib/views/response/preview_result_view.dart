import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../../widgets/ad_layouts/placeholder_ad.dart';
import 'previews/home_preview.dart';
import 'previews/menu_preview.dart';
import 'previews/promotions_preview.dart';
import 'previews/ride_summary_preview.dart';
import 'previews/search_preview.dart';
import 'previews/vehicle_selection_preview.dart';
import 'previews/waiting_preview.dart';
import 'response_details_view.dart';
import '../../mock_data.dart';

class PreviewResultView extends StatefulWidget {
  final Creative creative;
  final String placement;
  final String rawResponse;
  final DecisionRequest Function() requestBuilder;
  final AdMoai sdk;

  const PreviewResultView({
    super.key,
    required this.creative,
    required this.placement,
    required this.rawResponse,
    required this.requestBuilder,
    required this.sdk,
  });

  @override
  State<PreviewResultView> createState() => _PreviewResultViewState();
}

class _PreviewResultViewState extends State<PreviewResultView> {
  late Creative _creative;
  late String _rawResponse;

  @override
  void initState() {
    super.initState();
    _creative = widget.creative;
    _rawResponse = widget.rawResponse;
  }

  String get placementName {
    return placementMockData
        .firstWhere(
          (p) => p.id == widget.placement,
          orElse: () => PlacementData(
            id: widget.placement,
            name: widget.placement,
            icon: Icons.help_outline,
          ),
        )
        .name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              placementName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.placement,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'Monospace',
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withAlpha(128),
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => ResponseDetailsView(
                  creative: _creative,
                  rawResponse: _rawResponse,
                  sdk: widget.sdk,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                final request = widget.requestBuilder();
                final response = await widget.sdk.requestAds(request);

                final creative = response.body.data?.first.creatives?.first;
                if (creative == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No ads available')),
                    );
                  }
                  return;
                }

                setState(() {
                  _creative = creative;
                  _rawResponse = response.rawBody ?? '';
                });
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e is ClientError
                          ? 'Client Error: ${e.message}'
                          : 'Error: ${e.toString()}'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: switch (widget.placement) {
        'menu' => MenuPreview(creative: _creative, sdk: widget.sdk),
        'search' => SearchPreview(creative: _creative, sdk: widget.sdk),
        'promotions' => PromotionsPreview(creative: _creative, sdk: widget.sdk),
        'rideSummary' =>
          RideSummaryPreview(creative: _creative, sdk: widget.sdk),
        'home' => HomePreview(creative: _creative, sdk: widget.sdk),
        'waiting' => WaitingPreview(creative: _creative, sdk: widget.sdk),
        'vehicleSelection' =>
          VehicleSelectionPreview(creative: _creative, sdk: widget.sdk),
        _ => PlaceholderAdView(
            placement: widget.placement,
            template: _creative.template.key,
            style: _creative.template.style,
          ),
      },
    );
  }
}
