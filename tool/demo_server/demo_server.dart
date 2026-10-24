import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'demo_data.dart';
import 'png.dart';

/// Local Xtream Codes / M3U server with a fictional catalog, for visual tests
/// and manual review. Credentials are `demo` / `demo`.
class DemoServer {
  DemoServer._(
    this._server,
    this._clipFile,
    this._paced,
    this._unstableCutoff,
  ) {
    _server.listen(_handle);
  }

  /// Length of the clip in seconds, used to pace live streams.
  static const _clipSeconds = 12;

  /// Default location of the clip, relative to the repository root.
  static const defaultClipPath = 'tool/demo_server/assets/demo.ts';

  final HttpServer _server;
  final File _clipFile;
  final bool _paced;
  final Duration _unstableCutoff;

  /// When `true`, every route answers 503 (to test the offline state).
  bool down = false;

  /// Starts a server on loopback; [port] 0 picks a free one. [clipPath] is the
  /// MPEG-TS clip served by every stream route. Live and series streams loop the
  /// clip forever at about real time ([paced] false sends it as fast as the
  /// client reads); the unstable channel is cut after [unstableCutoff].
  static Future<DemoServer> start({
    int port = 0,
    String clipPath = defaultClipPath,
    bool paced = true,
    Duration unstableCutoff = const Duration(seconds: 45),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    return DemoServer._(server, File(clipPath), paced, unstableCutoff);
  }

  /// Base address, e.g. `http://127.0.0.1:8899`.
  Uri get baseUrl => Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);

  /// Stops the server, dropping open connections.
  Future<void> close() => _server.close(force: true);

  /// Routes one request; never throws, even if the client aborts mid-response.
  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (down) {
        response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        await _route(request);
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Headers already sent: nothing to change.
      }
    }
    try {
      await response.close();
    } catch (_) {
      // The client went away.
    }
  }

  /// Answers [request] according to its path.
  Future<void> _route(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final first = segments.isEmpty ? '' : segments.first;
    if (request.uri.path == '/player_api.php') {
      _writeJson(response, _playerApi(request.uri.queryParameters));
    } else if (request.uri.path == '/playlist.m3u') {
      _writeText(response, 'audio/x-mpegurl', _playlist());
    } else if (request.uri.path == '/xmltv.php') {
      _writeText(response, 'application/xml', _xmltv());
    } else if (first == 'img' && segments.length == 2) {
      final number = int.tryParse(segments[1].split('.').first);
      if (number == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers.contentType = ContentType('image', 'png');
        response.add(buildNumberedPng(number));
      }
    } else if (const {'live', 'movie', 'series'}.contains(first) &&
        segments.length == 4) {
      if (segments[1] != demoUser || segments[2] != demoPassword) {
        response.statusCode = HttpStatus.forbidden;
      } else {
        await _writeStream(request, segments[0], segments[3]);
      }
    } else {
      response.statusCode = HttpStatus.notFound;
    }
  }

  /// Serves the clip for a stream route. Movies are finite and support byte
  /// ranges; live and series loop the clip until the client leaves (the
  /// unstable channel stops after [_unstableCutoff]).
  Future<void> _writeStream(
    HttpRequest request,
    String kind,
    String fileName,
  ) async {
    final bytes = await _clipFile.readAsBytes();
    final response = request.response;
    response.headers.contentType = ContentType('video', 'mp2t');
    if (kind == 'movie') {
      _writeRange(request, bytes);
      return;
    }
    final id = int.tryParse(fileName.split('.').first);
    final cutoff = kind == 'live' && id == unstableChannelId
        ? _unstableCutoff
        : null;
    await _writeLoop(response, bytes, cutoff);
  }

  /// Sends [bytes] honoring a single `Range: bytes=a-b` header (206), or all
  /// of it (200) when there is none; an unsatisfiable range gets 416.
  void _writeRange(HttpRequest request, List<int> bytes) {
    final response = request.response;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final header = request.headers.value(HttpHeaders.rangeHeader);
    final match = header == null
        ? null
        : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
    if (match == null) {
      response.contentLength = bytes.length;
      response.add(bytes);
      return;
    }
    final startText = match.group(1)!;
    final endText = match.group(2)!;
    int start;
    int end;
    if (startText.isEmpty) {
      // Suffix range: the last N bytes.
      final suffix = int.tryParse(endText) ?? 0;
      start = (bytes.length - suffix).clamp(0, bytes.length);
      end = bytes.length - 1;
    } else {
      start = int.parse(startText);
      end = endText.isEmpty
          ? bytes.length - 1
          : int.parse(endText).clamp(0, bytes.length - 1);
    }
    if (start >= bytes.length || start > end) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );
      return;
    }
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/${bytes.length}',
    );
    response.contentLength = end - start + 1;
    response.add(bytes.sublist(start, end + 1));
  }

  /// Streams [bytes] in a loop with chunked encoding until the client
  /// disconnects or [cutoff] elapses (then the connection is closed).
  Future<void> _writeLoop(
    HttpResponse response,
    List<int> bytes,
    Duration? cutoff,
  ) async {
    // A multiple of the 188-byte TS packet, about 0.1 s of the clip.
    final chunkSize = (bytes.length ~/ 120) ~/ 188 * 188;
    final pause = Duration(
      milliseconds: _paced
          ? _clipSeconds * 1000 * chunkSize ~/ bytes.length
          : 0,
    );
    var disconnected = false;
    response.done.then((_) {}, onError: (_) {}).whenComplete(() {
      disconnected = true;
    });
    final stopwatch = Stopwatch()..start();
    var offset = 0;
    while (!disconnected && (cutoff == null || stopwatch.elapsed < cutoff)) {
      final end = offset + chunkSize > bytes.length
          ? bytes.length
          : offset + chunkSize;
      response.add(bytes.sublist(offset, end));
      offset = end == bytes.length ? 0 : end;
      await response.flush();
      await Future<void>.delayed(pause);
    }
  }

  /// Writes [body] as UTF-8 JSON.
  void _writeJson(HttpResponse response, Object? body) {
    _writeText(response, 'application/json', jsonEncode(body));
  }

  /// Writes [text] as UTF-8 with the given [mimeType].
  void _writeText(HttpResponse response, String mimeType, String text) {
    final bytes = utf8.encode(text);
    response.headers.contentType = ContentType.parse(
      '$mimeType; charset=utf-8',
    );
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  /// Poster URL of the item numbered [id].
  String _image(int id) => '${baseUrl.origin}/img/$id.png';

  /// Result of `player_api.php` for the query [params].
  Object? _playerApi(Map<String, String> params) {
    final authorized =
        params['username'] == demoUser && params['password'] == demoPassword;
    final action = params['action'];
    if (action == null) {
      return {
        'user_info': {
          'auth': authorized ? 1 : 0,
          'status': 'Active',
          'username': params['username'],
          'max_connections': '1',
          'allowed_output_formats': ['ts'],
        },
        'server_info': {
          'url': baseUrl.host,
          'port': '${baseUrl.port}',
          'server_protocol': 'http',
        },
      };
    }
    if (!authorized) {
      return {
        'user_info': {'auth': 0},
      };
    }
    switch (action) {
      case 'get_live_categories':
        return _categories(liveCategoryNames);
      case 'get_vod_categories':
        return _categories(movieCategoryNames);
      case 'get_series_categories':
        return _categories(seriesCategoryNames);
      case 'get_live_streams':
        final categoryId = params['category_id'];
        return [
          for (final channel in demoChannels)
            if (categoryId == null || categoryId == channel.categoryId)
              {
                'num': channel.id,
                'name': channel.name,
                'stream_type': 'live',
                'stream_id': channel.id,
                'stream_icon': _image(channel.id),
                'epg_channel_id': channel.epgId,
                'category_id': channel.categoryId,
              },
        ];
      case 'get_vod_streams':
        return [
          for (final movie in demoMovies)
            {
              'num': movie.id - 100,
              'name': movie.title,
              'stream_type': 'movie',
              'stream_id': movie.id,
              'stream_icon': _image(movie.id),
              'rating': '${6 + movie.id % 4}.${movie.id % 10}',
              'category_id': movie.categoryId,
              'container_extension': 'mp4',
            },
        ];
      case 'get_vod_info':
        return _movieInfo(int.tryParse(params['vod_id'] ?? ''));
      case 'get_series':
        return [
          for (final series in demoSeries)
            {
              'num': series.id - 200,
              'name': series.title,
              'series_id': series.id,
              'cover': _image(series.id),
              'rating': '${6 + series.id % 4}.${series.id % 10}',
              'category_id': series.categoryId,
            },
        ];
      case 'get_series_info':
        return _seriesInfo(int.tryParse(params['series_id'] ?? ''));
    }
    return [];
  }

  /// Categories as `get_*_categories` returns them (ids are strings).
  List<Map<String, Object?>> _categories(Map<String, String> names) => [
    for (final entry in names.entries)
      {'category_id': entry.key, 'category_name': entry.value, 'parent_id': 0},
  ];

  /// Answer of `get_vod_info` for the movie [id] (empty when unknown).
  Object? _movieInfo(int? id) {
    final movie = demoMovies.where((m) => m.id == id).firstOrNull;
    if (movie == null) return {'info': []};
    return {
      'info': {
        'movie_image': _image(movie.id),
        'plot':
            'Sinopsis inventada de "${movie.title}": una historia de '
            'ficción creada solo para pruebas.',
        'genre': movieCategoryNames[movie.categoryId],
        'director': 'Dirección Ficticia',
        'cast': 'Ana Imaginaria, Luis Inventado, Marta Supuesta',
        'releasedate': '${2000 + movie.id % 24}-05-1${movie.id % 10}',
        'duration_secs': 4800 + movie.id * 10,
      },
      'movie_data': {
        'stream_id': movie.id,
        'name': movie.title,
        'category_id': movie.categoryId,
        'container_extension': 'mp4',
      },
    };
  }

  /// Answer of `get_series_info` for the series [id] (empty when unknown).
  Object? _seriesInfo(int? id) {
    final series = demoSeries.where((s) => s.id == id).firstOrNull;
    if (series == null) return {'info': [], 'episodes': []};
    final seasons = <String, List<Map<String, Object?>>>{};
    for (final episode in series.episodes) {
      seasons.putIfAbsent('${episode.season}', () => []).add({
        'id': '${episode.id}',
        'episode_num': episode.number,
        'title': episode.title,
        'container_extension': 'ts',
        'season': episode.season,
        'info': {
          'plot': 'Argumento inventado de "${series.title}".',
          'duration_secs': 1500 + episode.number * 60,
          'movie_image': _image(episode.id),
        },
      });
    }
    return {
      'info': {
        'name': series.title,
        'cover': _image(series.id),
        'plot': 'Serie ficticia "${series.title}", creada solo para pruebas.',
        'genre': seriesCategoryNames[series.categoryId],
        'releaseDate': '${2010 + series.id % 14}-09-01',
      },
      'episodes': seasons,
    };
  }

  /// M3U with live channels, movies and series episodes.
  String _playlist() {
    final origin = baseUrl.origin;
    final out = StringBuffer(
      '#EXTM3U url-tvg="$origin/xmltv.php?username=$demoUser'
      '&password=$demoPassword"\n',
    );
    void entry(
      String tvgId,
      int imageId,
      String group,
      String name,
      String url,
    ) {
      out.writeln(
        '#EXTINF:-1 tvg-id="$tvgId" tvg-logo="${_image(imageId)}" '
        'group-title="$group",$name',
      );
      out.writeln(url);
    }

    final credentials = '$demoUser/$demoPassword';
    for (final channel in demoChannels) {
      entry(
        channel.epgId,
        channel.id,
        liveCategoryNames[channel.categoryId]!,
        channel.name,
        '$origin/live/$credentials/${channel.id}.ts',
      );
    }
    for (final movie in demoMovies) {
      entry(
        '',
        movie.id,
        movieCategoryNames[movie.categoryId]!,
        movie.title,
        '$origin/movie/$credentials/${movie.id}.mp4',
      );
    }
    for (final series in demoSeries) {
      for (final episode in series.episodes) {
        entry(
          '',
          series.id,
          seriesCategoryNames[series.categoryId]!,
          '${series.title} S${episode.season}E${episode.number}',
          '$origin/series/$credentials/${episode.id}.ts',
        );
      }
    }
    return out.toString();
  }

  /// XMLTV guide covering every live channel from now-6h to now+72h.
  String _xmltv() {
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    final out = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n');
    for (final channel in demoChannels) {
      out.writeln(
        '<channel id="${channel.epgId}"><display-name>'
        '${escape.convert(channel.name)}</display-name></channel>',
      );
    }
    for (final programme in demoProgrammes(DateTime.now())) {
      out.writeln(
        '<programme start="${_xmltvTime(programme.start)}" '
        'stop="${_xmltvTime(programme.stop)}" channel="${programme.channelId}">'
        '<title>${escape.convert(programme.title)}</title>'
        '<desc>Descripción ficticia de ${escape.convert(programme.title)}.</desc>'
        '</programme>',
      );
    }
    out.writeln('</tv>');
    return out.toString();
  }

  /// Formats a UTC time as XMLTV: `YYYYMMDDhhmmss +0000`.
  String _xmltvTime(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}${two(utc.hour)}${two(utc.minute)}${two(utc.second)} +0000';
  }
}
