import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class ContentsTabView extends StatelessWidget {
  final Creative creative;

  const ContentsTabView({super.key, required this.creative});

  Color? _colorFromHex(String? hexString) {
    if (hexString == null) return null;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.withAlpha(20),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: creative.contents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final content = creative.contents[index];
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        content.key,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontFamily: 'Courier',
                                ),
                      ),
                      Text(
                        content.type,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
                              fontFamily: 'Courier',
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (content.type == 'image')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        content.value ?? '',
                        fit: BoxFit.cover,
                      ),
                    )
                  else if (content.type == 'color')
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _colorFromHex(content.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          content.value ?? '',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontFamily: 'Courier'),
                        ),
                      ],
                    )
                  else
                    Text(
                      content.value ?? '',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
