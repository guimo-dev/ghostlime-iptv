import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// App canvas: the dark background with two faint lime glows.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.background),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.9, -1.1),
                  radius: 1.1,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.1, -1.0),
                  radius: 0.9,
                  colors: [
                    AppColors.accentAlt.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A heavily blurred image (usually a poster) fading into the background,
/// behind [child]. Used for hero banners and detail pages.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child, this.imageUrl});

  final String? imageUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return Stack(
      children: [
        if (url != null)
          Positioned.fill(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 40,
                  sigmaY: 40,
                  tileMode: TileMode.decal,
                ),
                child: Opacity(
                  opacity: 0.9,
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    // Tiny decode: it is blurred anyway.
                    cacheWidth: 320,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.background.withValues(alpha: 0.7),
                  AppColors.background.withValues(alpha: 0.15),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.background],
                stops: const [0.3, 1],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Red "EN DIRECTO" pill.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'EN DIRECTO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Thin progress bar filled with the accent gradient.
class GradientProgress extends StatelessWidget {
  const GradientProgress({super.key, required this.value, this.height = 4});

  /// Fraction 0–1.
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: const DecoratedBox(
                  key: Key('gradient-progress-fill'),
                  decoration: BoxDecoration(gradient: AppStyle.accentGradient),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
