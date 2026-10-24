import 'package:flutter/material.dart';

/// Small channel logo with a fallback icon when missing or broken.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.live_tv);
    final logo = url;
    if (logo == null) return fallback;
    return SizedBox(
      width: 40,
      height: 28,
      child: Image.network(
        logo,
        fit: BoxFit.contain,
        cacheWidth: 80,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Movie/series poster (2:3) with a fallback when missing or broken.
class Poster extends StatelessWidget {
  const Poster({super.key, this.url, this.cacheWidth = 300, this.radius = 10});

  final String? url;

  /// Decode width in pixels, to keep memory low in long grids.
  final int cacheWidth;

  /// Corner radius; 0 when the parent already clips.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 40, color: Colors.white24),
      ),
    );
    final poster = url;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: poster == null
            ? fallback
            : Image.network(
                poster,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
