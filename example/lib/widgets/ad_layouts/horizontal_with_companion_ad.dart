import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';
import '../skeleton/skeleton_shape.dart';

class HorizontalWithCompanionAd extends StatelessWidget {
  final Creative creative;
  final VoidCallback? onCompanionOpen;
  final ValueChanged<String>? onImpression;
  final ValueChanged<String>? onAdClick;

  const HorizontalWithCompanionAd({
    super.key,
    required this.creative,
    this.onCompanionOpen,
    this.onImpression,
    this.onAdClick,
  });

  bool get isImageRight => creative.template.style == 'imageRight';
  bool get isImageOnly => creative.template.style == 'wideImageOnly';

  String? get wideImage => creative.contents.getContent('wideImage')?.value;
  String? get squareImage => creative.contents.getContent('squareImage')?.value;
  String? get headline => creative.contents.getContent('headline')?.value;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4, // 4:1 ratio
      child: GestureDetector(
        onTap: () {
          onCompanionOpen?.call();
          showDialog(
            context: context,
            builder: (_) => CompanionDialog(
              creative: creative,
              onAdClick: onAdClick,
            ),
          );
        },
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child:
              isImageOnly ? _buildImageOnlyLayout() : _buildHorizontalLayout(),
        ),
      ),
    );
  }

  Widget _buildHorizontalLayout() {
    return Row(
      children: [
        if (!isImageRight) _buildAdImage(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (headline != null)
                  Text(
                    headline!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const Spacer(),
                _buildAdvertiserInfo(),
              ],
            ),
          ),
        ),
        if (isImageRight) _buildAdImage(),
      ],
    );
  }

  Widget _buildImageOnlyLayout() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildWideImage(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withAlpha(128), // 0.5 opacity
                  Colors.black.withAlpha(0),
                ],
              ),
            ),
            child: _buildAdvertiserInfo(isOverlay: true),
          ),
        ),
      ],
    );
  }

  Widget _buildWideImage() {
    if (wideImage == null) {
      return const SkeletonShape(
        type: SkeletonType.rectangle,
        cornerRadius: 0,
      );
    }

    return ClipRRect(
      child: Image.network(
        wideImage!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.withAlpha(51),
            child: const Center(
              child: Icon(Icons.image, color: Colors.grey),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdImage() {
    if (squareImage == null) {
      return AspectRatio(
        aspectRatio: 1,
        child: const SkeletonShape(
          type: SkeletonType.rectangle,
          cornerRadius: 0,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Image.network(
        squareImage!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.withAlpha(51),
            child: const Center(
              child: Icon(Icons.image, color: Colors.grey),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdvertiserInfo({bool isOverlay = false}) {
    return Row(
      children: [
        _buildAdvertiserLogo(),
        const SizedBox(width: 8),
        Text(
          creative.advertiser.name,
          style: TextStyle(
            fontSize: 12,
            color: isOverlay ? Colors.white : Colors.grey,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Ad',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvertiserLogo() {
    return SizedBox(
      width: 16,
      height: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          creative.advertiser.logoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.business,
              size: 16,
              color: Colors.grey,
            );
          },
        ),
      ),
    );
  }
}

class CompanionDialog extends StatelessWidget {
  final Creative creative;
  final ValueChanged<String>? onAdClick;

  const CompanionDialog({
    super.key,
    required this.creative,
    this.onAdClick,
  });

  String? get coverImage => creative.contents.getContent('coverImage')?.value;
  String? get headline => creative.contents.getContent('headline')?.value;
  String? get body => creative.contents.getContent('body')?.value;
  String? get cta => creative.contents.getContent('cta')?.value;
  String? get buttonColor => creative.contents.getContent('buttonColor')?.value;
  String? get buttonTextColor =>
      creative.contents.getContent('buttonTextColor')?.value;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 48,
          maxHeight: MediaQuery.of(context).size.height - 80,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (coverImage != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.91,
                    child: Image.network(
                      coverImage!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (headline != null)
                      Text(
                        headline!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    if (body != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        body!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                      ),
                    ],
                    if (cta != null) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          onAdClick?.call('default');
                          Navigator.pop(context);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Color(
                              int.parse('0xFF${buttonColor?.substring(1)}')),
                          foregroundColor: Color(int.parse(
                              '0xFF${buttonTextColor?.substring(1)}')),
                        ),
                        child: Text(cta!),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Image.network(
                          creative.advertiser.logoUrl,
                          width: 16,
                          height: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          creative.advertiser.name,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Ad',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
