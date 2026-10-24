import 'package:flutter/material.dart';

/// Widest the content of a screen grows, so rows stay readable in a maximized
/// window.
abstract final class ContentWidths {
  /// Lists and forms read as rows: label and control stay close together.
  static const reading = 900.0;

  /// Grids of cards can use more of the window.
  static const grid = 1400.0;
}

/// Centers [child] horizontally and limits it to [maxWidth].
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = ContentWidths.reading,
  });

  final Widget child;
  final double maxWidth;

  /// [padding] plus the side margins that keep the content of a scroll view
  /// [width] wide centered within [maxWidth], as if wrapped in a
  /// [ContentWidth].
  ///
  /// Scroll views use this instead of sitting inside a [ContentWidth], so the
  /// mouse wheel also works over the side margins.
  static EdgeInsets paddingFor(
    double width,
    EdgeInsets padding, {
    double maxWidth = ContentWidths.reading,
  }) {
    final margin = width > maxWidth ? (width - maxWidth) / 2 : 0.0;
    return padding + EdgeInsets.symmetric(horizontal: margin);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
