import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The Ghostlime icon: a lime ghost whose face is a dark play button.
///
/// Drawn from the paths of `branding/ghostlime.svg` (coordinates 0..120).
/// With [tile] it sits on the dark rounded square of the app icon; without
/// it only the ghost is painted.
class GhostlimeLogo extends StatelessWidget {
  const GhostlimeLogo({
    super.key,
    this.size = 48,
    this.tile = true,
    this.semanticLabel,
  });

  /// Width and height of the logo.
  final double size;

  /// Whether to paint the dark rounded square behind the ghost.
  final bool tile;

  /// Spoken description; `null` for a decorative logo, left out of semantics.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final logo = CustomPaint(
      size: Size.square(size),
      painter: _GhostlimePainter(tile),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: logo);
    return Semantics(label: label, image: true, child: logo);
  }
}

/// Paints the Ghostlime icon scaled to the canvas size.
class _GhostlimePainter extends CustomPainter {
  const _GhostlimePainter(this.tile);

  final bool tile;

  /// Side of the square the SVG paths are drawn in.
  static const _viewBox = 120.0;

  static final _body = Path()
    ..moveTo(28, 102)
    ..lineTo(28, 56)
    ..arcToPoint(const Offset(92, 56), radius: const Radius.circular(32))
    ..lineTo(92, 102)
    ..lineTo(81, 92)
    ..lineTo(71, 102)
    ..lineTo(60, 92)
    ..lineTo(49, 102)
    ..lineTo(39, 92)
    ..close();

  static final _play = Path()
    ..moveTo(52, 46)
    ..lineTo(76, 60)
    ..lineTo(52, 74)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.width * 240 / 1024),
        ),
        Paint()..color = AppColors.onAccent,
      );
    }
    canvas.save();
    canvas.scale(size.width / _viewBox);
    canvas.translate(0, -3);
    canvas.drawPath(_body, Paint()..color = AppColors.accent);
    canvas.drawPath(_play, Paint()..color = AppColors.onAccent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GhostlimePainter oldDelegate) => oldDelegate.tile != tile;
}
