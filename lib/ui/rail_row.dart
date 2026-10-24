import 'package:flutter/material.dart';

/// A titled horizontal carousel, as used on the home screen.
class RailRow extends StatelessWidget {
  const RailRow({
    super.key,
    required this.title,
    required this.height,
    required this.children,
  });

  final String title;

  /// Height of the scrolling strip (items size themselves inside it).
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (_, index) => children[index],
          ),
        ),
      ],
    );
  }
}
