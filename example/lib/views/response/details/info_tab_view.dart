import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class InfoTabView extends StatelessWidget {
  final Creative creative;

  const InfoTabView({super.key, required this.creative});

  Widget _buildCard({
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildInfoItem(BuildContext context, String label, String value) {
    return ListTile(
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      subtitle: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontFamily: 'Courier'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Advertiser',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        _buildAdvertiserSection(context),
        const SizedBox(height: 24),
        Text(
          'Template',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        _buildTemplateSection(context),
        if (creative.metadata != null) ...[
          const SizedBox(height: 24),
          Text(
            'Metadata',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          _buildMetadataSection(context),
        ],
      ],
    );
  }

  Widget _buildAdvertiserSection(BuildContext context) {
    return _buildCard(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            creative.advertiser.logoUrl,
            width: 40,
            height: 40,
          ),
        ),
        title: Text(creative.advertiser.name),
        subtitle: Text(
          creative.advertiser.legalName,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _buildTemplateSection(BuildContext context) {
    return _buildCard(
      child: Column(
        children: [
          _buildInfoItem(context, 'Key', creative.template.key),
          const Divider(height: 1),
          _buildInfoItem(context, 'Style', creative.template.style),
        ],
      ),
    );
  }

  Widget _buildMetadataSection(BuildContext context) {
    final metadata = creative.metadata!;
    return _buildCard(
      child: Column(
        children: [
          _buildInfoItem(context, 'Ad ID', metadata.adId),
          const Divider(height: 1),
          _buildInfoItem(context, 'Creative ID', metadata.creativeId),
          const Divider(height: 1),
          _buildInfoItem(context, 'Advertiser ID', metadata.advertiserId),
          const Divider(height: 1),
          _buildInfoItem(context, 'Template ID', metadata.templateId),
          const Divider(height: 1),
          _buildInfoItem(context, 'Placement ID', metadata.placementId),
          const Divider(height: 1),
          _buildInfoItem(context, 'Priority', metadata.priority),
          const Divider(height: 1),
          _buildInfoItem(context, 'Language', metadata.language),
        ],
      ),
    );
  }
}
