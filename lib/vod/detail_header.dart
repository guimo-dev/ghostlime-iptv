import 'package:flutter/material.dart';

import '../browse/catalog_images.dart';
import '../ui/app_theme.dart';
import '../ui/display_title.dart';

/// Header of a movie or series page (place it over a [Backdrop]):
/// large poster, clean title, metadata chips (the name's year and tags plus
/// [chips]), action buttons and an optional body (plot, credits).
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.title,
    required this.actions,
    this.posterUrl,
    this.chips = const [],
    this.body,
  });

  /// Provider name; cleaned with [displayTitle] for display.
  final String title;
  final String? posterUrl;

  /// Extra facts such as genre, duration or rating.
  final List<String> chips;
  final List<Widget> actions;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clean = displayTitle(title);
    final allChips = [...clean.details, ...chips];
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 72, 48, 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 250,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppStyle.cardShadow,
              ),
              child: Poster(url: posterUrl, cacheWidth: 500, radius: 14),
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(clean.title, style: text.displaySmall),
                  if (allChips.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final chip in allChips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              chip,
                              style: text.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(spacing: 12, runSpacing: 12, children: actions),
                  if (body != null) ...[const SizedBox(height: 24), body!],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
