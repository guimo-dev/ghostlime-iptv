import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ghostlime_logo.dart';

/// Empty or error state: the ghost mascot above a [title], an optional
/// [message] and an optional [child] (usually a button). The ghost is dimmed
/// when [dimmed] is set, for errors.
class BrandMessage extends StatelessWidget {
  const BrandMessage({
    super.key,
    required this.title,
    this.message,
    this.child,
    this.logoSize = 80,
    this.dimmed = false,
  });

  final String title;
  final String? message;

  /// Extra content below the texts, e.g. a retry button.
  final Widget? child;
  final double logoSize;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final message = this.message;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Opacity(
          opacity: dimmed ? 0.35 : 0.7,
          child: GhostlimeLogo(size: logoSize, tile: false),
        ),
        Text(title, style: text.titleMedium, textAlign: TextAlign.center),
        if (message != null)
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ?child,
      ],
    );
  }
}

/// Branded loading indicator: the ghost floating over a soft accent pulse.
/// Static when the platform asks to disable animations.
class BrandLoader extends StatefulWidget {
  const BrandLoader({super.key, this.size = 64});

  final double size;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final accent = AccentPalette.of(context).accent;
    return Semantics(
      label: 'Cargando',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Transform.translate(
            offset: Offset(0, -size * 0.08 * t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.10 + 0.14 * t),
                    blurRadius: size * 0.6,
                    spreadRadius: size * 0.05 * t,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: GhostlimeLogo(size: size, tile: false),
      ),
    );
  }
}
