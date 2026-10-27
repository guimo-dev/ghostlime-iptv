import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../ui/app_theme.dart';
import '../ui/focus_card.dart';

/// Background of the panels of the TV players, over the picture.
const tvPanelColor = Color(0xE60D0E15);

/// The quick options of the TV players: the audio and subtitle tracks of
/// [player]; OK picks one. The first option takes the focus when it
/// appears.
class TvTrackOptions extends StatefulWidget {
  /// The tracks of [player].
  const TvTrackOptions({super.key, required this.player});

  /// The player whose tracks are shown and changed.
  final Player player;

  @override
  State<TvTrackOptions> createState() => _TvTrackOptionsState();
}

class _TvTrackOptionsState extends State<TvTrackOptions> {
  final _firstNode = FocusNode(debugLabel: 'TV first option');

  /// Tracks picked here, shown as selected before the player reports them.
  String? _audioId;
  String? _subtitleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstNode.dispose();
    super.dispose();
  }

  /// The label of an audio or subtitle track.
  static String _label(String id, String? title, String? language) =>
      switch (id) {
        'auto' => 'Automático',
        'no' => 'Desactivados',
        _ => title ?? language ?? 'Pista $id',
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = widget.player.state;
    final audioId = _audioId ?? state.track.audio.id;
    final subtitleId = _subtitleId ?? state.track.subtitle.id;
    final audio = [
      for (final track in state.tracks.audio)
        if (track.id != 'no') track,
    ];
    final subtitles = state.tracks.subtitle;
    var first = true;
    Widget option(String label, bool selected, VoidCallback onTap) {
      final node = first ? _firstNode : null;
      first = false;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: FocusCard(
          grow: false,
          selected: selected,
          focusNode: node,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                Icon(
                  selected ? Icons.check : null,
                  size: 18,
                  color: AccentPalette.of(context).accent,
                ),
                Expanded(child: Text(label)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('tv-options'),
      width: 340,
      color: tvPanelColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Audio', style: text.titleMedium),
          if (audio.isEmpty)
            Text('Sin pistas', style: text.bodySmall)
          else
            for (final track in audio)
              option(
                _label(track.id, track.title, track.language),
                track.id == audioId,
                () {
                  setState(() => _audioId = track.id);
                  widget.player.setAudioTrack(track);
                },
              ),
          const SizedBox(height: 16),
          Text('Subtítulos', style: text.titleMedium),
          if (subtitles.isEmpty)
            Text('Sin pistas', style: text.bodySmall)
          else
            for (final track in subtitles)
              option(
                _label(track.id, track.title, track.language),
                track.id == subtitleId,
                () {
                  setState(() => _subtitleId = track.id);
                  widget.player.setSubtitleTrack(track);
                },
              ),
        ],
      ),
    );
  }
}
