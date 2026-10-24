/// A live TV category as returned by `get_live_categories`.
class LiveCategory {
  const LiveCategory({required this.id, required this.name});

  /// Parses one category; ids may come as numbers or strings.
  factory LiveCategory.fromJson(Map<String, dynamic> json) {
    return LiveCategory(
      id: _asString(json['category_id']) ?? '',
      name: _asString(json['category_name']) ?? '',
    );
  }

  final String id;
  final String name;
}

/// A live channel as returned by `get_live_streams`.
class LiveStream {
  const LiveStream({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.iconUrl,
    this.epgChannelId,
  });

  /// Parses one channel, tolerating number/string ids and empty or null fields.
  factory LiveStream.fromJson(Map<String, dynamic> json) {
    return LiveStream(
      streamId: int.tryParse(_asString(json['stream_id']) ?? '') ?? 0,
      name: _asString(json['name']) ?? '',
      categoryId: _asString(json['category_id']) ?? '',
      iconUrl: _asString(json['stream_icon']),
      epgChannelId: _asString(json['epg_channel_id']),
    );
  }

  final int streamId;
  final String name;
  final String categoryId;
  final String? iconUrl;
  final String? epgChannelId;
}

/// A movie as returned by `get_vod_streams`.
class VodStream {
  const VodStream({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.iconUrl,
    this.extension,
    this.rating,
  });

  /// Parses one movie, tolerating number/string fields and empty values.
  factory VodStream.fromJson(Map<String, dynamic> json) {
    return VodStream(
      streamId: _asInt(json['stream_id']) ?? 0,
      name: _asString(json['name']) ?? '',
      categoryId: _asString(json['category_id']) ?? '',
      iconUrl: _asString(json['stream_icon']),
      extension: _asString(json['container_extension']),
      rating: _asDouble(json['rating']),
    );
  }

  final int streamId;
  final String name;
  final String categoryId;
  final String? iconUrl;
  final String? extension;
  final double? rating;
}

/// A series (show) as returned by `get_series`.
class SeriesItem {
  const SeriesItem({
    required this.seriesId,
    required this.name,
    required this.categoryId,
    this.coverUrl,
    this.rating,
  });

  /// Parses one series, tolerating number/string fields and empty values.
  factory SeriesItem.fromJson(Map<String, dynamic> json) {
    return SeriesItem(
      seriesId: _asInt(json['series_id']) ?? 0,
      name: _asString(json['name']) ?? '',
      categoryId: _asString(json['category_id']) ?? '',
      coverUrl: _asString(json['cover']),
      rating: _asDouble(json['rating']),
    );
  }

  final int seriesId;
  final String name;
  final String categoryId;
  final String? coverUrl;
  final double? rating;
}

/// One episode of `get_series_info`.
class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.extension,
    this.plot,
    this.durationSecs,
    this.imageUrl,
  });

  /// Parses one episode; [fallbackSeason] is used when it carries no `season`.
  factory Episode.fromJson(Map<String, dynamic> json, int fallbackSeason) {
    final info = _asMap(json['info']);
    return Episode(
      id: _asInt(json['id']) ?? 0,
      season: _asInt(json['season']) ?? fallbackSeason,
      number: _asInt(json['episode_num']) ?? 0,
      title: _asString(json['title']) ?? '',
      extension: _asString(json['container_extension']),
      plot: _asString(info['plot']),
      durationSecs: _asInt(info['duration_secs']),
      imageUrl: _asString(info['movie_image']),
    );
  }

  final int id;
  final int season;
  final int number;
  final String title;
  final String? extension;
  final String? plot;
  final int? durationSecs;
  final String? imageUrl;
}

/// The answer of `get_series_info`: show details and episodes by season.
class SeriesInfo {
  const SeriesInfo({
    this.plot,
    this.genre,
    this.releaseDate,
    this.coverUrl,
    this.seasons = const {},
  });

  /// Parses the whole answer. `episodes` may be a season → list map or a flat
  /// list, and `info` may be `[]`; seasons without episodes are dropped.
  factory SeriesInfo.fromJson(Map<String, dynamic> json) {
    final info = _asMap(json['info']);
    final rawEpisodes = json['episodes'];
    final episodes = <Episode>[];
    if (rawEpisodes is Map) {
      rawEpisodes.forEach((key, list) {
        final keySeason = int.tryParse('$key') ?? 0;
        if (list is! List) return;
        for (final item in list.whereType<Map<String, dynamic>>()) {
          episodes.add(Episode.fromJson(item, keySeason));
        }
      });
    } else if (rawEpisodes is List) {
      for (final item in rawEpisodes.whereType<Map<String, dynamic>>()) {
        episodes.add(Episode.fromJson(item, 0));
      }
    }
    final bySeason = <int, List<Episode>>{};
    for (final episode in episodes) {
      bySeason.putIfAbsent(episode.season, () => []).add(episode);
    }
    final seasonNumbers = bySeason.keys.toList()..sort();
    return SeriesInfo(
      plot: _asString(info['plot']),
      genre: _asString(info['genre']),
      releaseDate: _asString(info['releaseDate'] ?? info['release_date']),
      coverUrl: _asString(info['cover']),
      seasons: {
        for (final season in seasonNumbers)
          season: bySeason[season]!
            ..sort((a, b) => a.number.compareTo(b.number)),
      },
    );
  }

  final String? plot;
  final String? genre;
  final String? releaseDate;
  final String? coverUrl;

  /// Episodes by season number, seasons ascending, episodes by number.
  final Map<int, List<Episode>> seasons;
}

/// Movie details from `get_vod_info`.
class MovieInfo {
  const MovieInfo({
    this.plot,
    this.genre,
    this.director,
    this.cast,
    this.releaseDate,
    this.durationSecs,
  });

  /// Parses the whole answer; `info` may be `[]` instead of an object.
  factory MovieInfo.fromJson(Map<String, dynamic> json) {
    final info = _asMap(json['info']);
    return MovieInfo(
      plot: _asString(info['plot']),
      genre: _asString(info['genre']),
      director: _asString(info['director']),
      cast: _asString(info['cast']),
      releaseDate: _asString(info['releasedate'] ?? info['release_date']),
      durationSecs: _asInt(info['duration_secs']),
    );
  }

  final String? plot;
  final String? genre;
  final String? director;
  final String? cast;
  final String? releaseDate;
  final int? durationSecs;
}

/// Converts a JSON scalar to a trimmed string, or `null` when missing or empty.
String? _asString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// Converts a JSON number or numeric string to an int, or `null`.
int? _asInt(Object? value) => int.tryParse(_asString(value) ?? '');

/// Converts a JSON number or numeric string to a double, or `null`.
double? _asDouble(Object? value) => double.tryParse(_asString(value) ?? '');

/// [value] when it is a JSON object, otherwise an empty map (some panels send
/// `[]` for an empty object).
Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};
