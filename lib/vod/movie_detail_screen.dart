import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../player/play_target.dart';
import '../player/resume.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../ui/backdrop.dart';
import '../ui/back_on_escape.dart';
import 'detail_header.dart';
import 'xtream_info.dart';

/// Movie page: poster, details (Xtream only) and play/resume.
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
    required this.movie,
  });

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;
  final Channel movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  late final int _playlistId = widget.playlist.id!;
  late final PlayTarget _target = PlayTarget.fromChannel(widget.movie);
  late final Future<MovieDetails?> _details = loadMovieDetails(
    widget.playlist,
    widget.passwords,
    widget.movie,
  );
  late bool _favorite = _isFavorite();

  bool _isFavorite() => widget.db
      .favoriteKeys(_playlistId, MediaKind.movie)
      .contains(widget.movie.key);

  Progress? get _progress =>
      widget.db.progress(_playlistId, MediaKind.movie, widget.movie.key);

  void _toggleFavorite() {
    widget.db.setFavorite(
      _playlistId,
      MediaKind.movie,
      widget.movie.key,
      !_favorite,
    );
    setState(() => _favorite = _isFavorite());
  }

  Future<void> _play() async {
    await playWithResume(
      context,
      db: widget.db,
      playlist: widget.playlist,
      passwords: widget.passwords,
      target: _target,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final unfinished = progress != null && progress.isUnfinished;
    return BackOnEscape(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Backdrop(
          imageUrl: widget.movie.iconUrl,
          child: FutureBuilder<MovieDetails?>(
            future: _details,
            builder: (context, snapshot) {
              final details = snapshot.data;
              final rows = details?.rows ?? const <(String, String)>[];
              const chipLabels = {'Género', 'Duración', 'Valoración'};
              return ListView(
                children: [
                  DetailHeader(
                    title: widget.movie.name,
                    posterUrl: widget.movie.iconUrl,
                    chips: [
                      for (final (label, value) in rows)
                        if (chipLabels.contains(label))
                          label == 'Valoración' ? '★ $value' : value,
                    ],
                    actions: [
                      FilledButton.icon(
                        autofocus: true,
                        onPressed: _play,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          unfinished
                              ? 'Reanudar desde ${formatDuration(progress.position)}'
                              : 'Reproducir',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _toggleFavorite,
                        icon: Icon(_favorite ? Icons.star : Icons.star_border),
                        label: Text(_favorite ? 'En favoritos' : 'Favorito'),
                      ),
                    ],
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (unfinished)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: SizedBox(
                              width: 320,
                              child: LinearProgressIndicator(
                                value:
                                    progress.position.inMilliseconds /
                                    progress.duration.inMilliseconds,
                              ),
                            ),
                          ),
                        if (snapshot.connectionState != ConnectionState.done)
                          const SizedBox(
                            width: 320,
                            child: LinearProgressIndicator(),
                          )
                        else if (details != null)
                          DetailsText(
                            rows: [
                              for (final row in rows)
                                if (!chipLabels.contains(row.$1)) row,
                            ],
                            plot: details.plot,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
