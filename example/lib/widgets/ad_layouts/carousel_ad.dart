import 'dart:async';
import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class CarouselSlide {
  final int id;
  final String image;
  final String headline;
  final String cta;
  final String url;

  CarouselSlide({
    required this.id,
    required this.image,
    required this.headline,
    required this.cta,
    required this.url,
  });
}

class CarouselAdView extends StatefulWidget {
  final Creative creative;
  final AdMoai sdk;

  const CarouselAdView({
    super.key,
    required this.creative,
    required this.sdk,
  });

  @override
  State<CarouselAdView> createState() => _CarouselAdViewState();
}

class _CarouselAdViewState extends State<CarouselAdView> {
  final _pageController = PageController(
    viewportFraction: 0.85,
    initialPage: 0,
  );
  int _currentIndex = 0;
  bool _isUserScrolling = false;
  Timer? _autoScrollTimer;

  List<CarouselSlide> get slides {
    return List.generate(3, (index) {
      final i = index + 1;
      final imageContent = widget.creative.contents.firstWhere(
        (c) => c.key == 'imageSlide$i',
        orElse: () => Content(key: 'imageSlide$i', value: null, type: ''),
      );
      final headlineContent = widget.creative.contents.firstWhere(
        (c) => c.key == 'headlineSlide$i',
        orElse: () => Content(key: 'headlineSlide$i', value: null, type: ''),
      );

      return CarouselSlide(
        id: i,
        image: imageContent.value ?? '',
        headline: headlineContent.value ?? '',
        cta: widget.creative.contents
                .firstWhere(
                  (c) => c.key == 'ctaSlide$i',
                  orElse: () =>
                      Content(key: 'ctaSlide$i', value: null, type: ''),
                )
                .value ??
            '',
        url: widget.creative.contents
                .firstWhere(
                  (c) => c.key == 'URLSlide$i',
                  orElse: () =>
                      Content(key: 'URLSlide$i', value: null, type: ''),
                )
                .value ??
            '',
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isUserScrolling && mounted) {
        final nextPage = (_currentIndex + 1) % slides.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    try {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth * 0.8;
          final imageHeight = cardWidth * 9 / 16;

          return SizedBox(
            height: imageHeight + 130,
            child: GestureDetector(
              onPanDown: (_) => _isUserScrolling = true,
              onPanEnd: (_) => _isUserScrolling = false,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemCount: slides.length,
                physics: const PageScrollPhysics(),
                itemBuilder: (context, index) {
                  final slide = slides[index];
                  return Center(
                    child: SizedBox(
                      width: cardWidth,
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.network(
                                slide.image,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  color: Theme.of(context).colorScheme.surface,
                                  child: Icon(
                                    Icons.image,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 120,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      slide.headline,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'Join Today',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Image.network(
                                            widget.creative.advertiser.logoUrl,
                                            width: 16,
                                            height: 16,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Icon(
                                              Icons.business,
                                              size: 16,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'AdMoai',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Ad',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Colors.white,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }
}
