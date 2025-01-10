import 'package:flutter/material.dart';

enum SkeletonType {
  circle,
  rectangle,
  text,
}

class SkeletonShape extends StatelessWidget {
  final SkeletonType type;
  final double? width;
  final double? height;
  final double cornerRadius;
  final int lines;
  final double spacing;

  const SkeletonShape({
    super.key,
    required this.type,
    this.width,
    this.height,
    this.cornerRadius = 4,
    this.lines = 1,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case SkeletonType.circle:
        return Container(
          width: width ?? 40,
          height: height ?? 40,
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(51),
            shape: BoxShape.circle,
          ),
        );
      case SkeletonType.rectangle:
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(51),
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        );
      case SkeletonType.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(lines, (index) {
            return Padding(
              padding: EdgeInsets.only(bottom: index < lines - 1 ? spacing : 0),
              child: Row(
                children: [
                  Expanded(
                    flex: lines > 1 && index == lines - 1 ? 6 : 10,
                    child: Container(
                      height: height ?? 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(51),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (lines > 1 && index == lines - 1) const Spacer(flex: 4),
                ],
              ),
            );
          }),
        );
    }
  }
}
