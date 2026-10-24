import 'package:flutter/material.dart';

import '../catalog/catalog_models.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../player/resume.dart';
import '../xtream/xtream_client.dart';
import '../xtream/xtream_credentials.dart';
import '../xtream/xtream_models.dart';

/// Displayable movie or series details.
class MovieDetails {
  const MovieDetails({this.plot, this.rows = const []});

  final String? plot;

  /// Label/value pairs such as genre or duration.
  final List<(String, String)> rows;
}

/// Opens an Xtream client for [playlist], or `null` for M3U or missing password.
Future<XtreamClient?> openXtreamClient(
  Playlist playlist,
  PasswordStore passwords,
) async {
  if (playlist.type != PlaylistType.xtream) return null;
  final password = await passwords.read(playlist.id!);
  if (password == null) return null;
  return XtreamClient(
    XtreamCredentials(
      playlist.serverUrl ?? '',
      playlist.username ?? '',
      password,
    ),
    userAgent: playlist.userAgent,
  );
}

/// Loads movie details from the Xtream panel; `null` for M3U or on error.
Future<MovieDetails?> loadMovieDetails(
  Playlist playlist,
  PasswordStore passwords,
  Channel movie,
) async {
  final streamId = movie.streamId;
  if (streamId == null) return null;
  final client = await openXtreamClient(playlist, passwords);
  if (client == null) return null;
  try {
    final info = await client.getVodInfo(streamId);
    final duration = info.durationSecs;
    return MovieDetails(
      plot: info.plot,
      rows: [
        if (info.genre != null) ('Género', info.genre!),
        if (info.releaseDate != null) ('Estreno', info.releaseDate!),
        if (duration != null && duration > 0)
          ('Duración', formatDuration(Duration(seconds: duration))),
        if (info.director != null) ('Dirección', info.director!),
        if (info.cast != null) ('Reparto', info.cast!),
        if (movie.rating != null && movie.rating! > 0)
          ('Valoración', movie.rating!.toStringAsFixed(1)),
      ],
    );
  } on XtreamException {
    return null;
  } finally {
    client.close();
  }
}

/// Loads a series' seasons and details from the Xtream panel; `null` on error.
Future<SeriesInfo?> loadSeriesInfo(
  Playlist playlist,
  PasswordStore passwords,
  int seriesId,
) async {
  final client = await openXtreamClient(playlist, passwords);
  if (client == null) return null;
  try {
    return await client.getSeriesInfo(seriesId);
  } on XtreamException {
    return null;
  } finally {
    client.close();
  }
}

/// Label/value rows followed by the plot.
class DetailsText extends StatelessWidget {
  const DetailsText({super.key, required this.rows, this.plot});

  final List<(String, String)> rows;
  final String? plot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        if (plot != null && plot!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(plot!, style: text.bodyLarge),
        ],
      ],
    );
  }
}
