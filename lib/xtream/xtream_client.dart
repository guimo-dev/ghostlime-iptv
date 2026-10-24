import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'xtream_credentials.dart';
import 'xtream_models.dart';
import 'xtream_urls.dart';

/// Error shown to the user when talking to an Xtream server fails.
///
/// [message] is in Spanish and never contains the request URL (it holds the password).
class XtreamException implements Exception {
  const XtreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal client for the Xtream Codes `player_api.php` API.
class XtreamClient {
  /// Creates a client for [credentials]; [httpClient] is injectable for tests.
  /// [userAgent], when set, is sent on every request.
  XtreamClient(this.credentials, {http.Client? httpClient, this.userAgent})
    : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 20);

  final XtreamCredentials credentials;
  final String? userAgent;
  final http.Client _http;

  /// Checks the credentials; throws [XtreamException] when the server rejects them.
  Future<void> authenticate() async {
    final json = await _getJson();
    final userInfo = json is Map ? json['user_info'] : null;
    final auth = userInfo is Map ? userInfo['auth'].toString() : null;
    if (auth != '1') {
      throw const XtreamException(
        'El servidor ha rechazado las credenciales de la lista.',
      );
    }
  }

  /// Returns all live TV categories.
  Future<List<LiveCategory>> getLiveCategories() async {
    final json = await _getJson(action: 'get_live_categories');
    return _asMaps(json).map(LiveCategory.fromJson).toList();
  }

  /// Returns live channels, all of them or only those in [categoryId].
  Future<List<LiveStream>> getLiveStreams({String? categoryId}) async {
    final json = await _getJson(
      action: 'get_live_streams',
      params: {'category_id': ?categoryId},
    );
    return _asMaps(json).map(LiveStream.fromJson).toList();
  }

  /// Returns all movie categories.
  Future<List<LiveCategory>> getVodCategories() async {
    final json = await _getJson(action: 'get_vod_categories');
    return _asMaps(json).map(LiveCategory.fromJson).toList();
  }

  /// Returns all movies.
  Future<List<VodStream>> getVodStreams() async {
    final json = await _getJson(action: 'get_vod_streams');
    return _asMaps(json).map(VodStream.fromJson).toList();
  }

  /// Returns all series categories.
  Future<List<LiveCategory>> getSeriesCategories() async {
    final json = await _getJson(action: 'get_series_categories');
    return _asMaps(json).map(LiveCategory.fromJson).toList();
  }

  /// Returns all series (shows, without episodes).
  Future<List<SeriesItem>> getSeries() async {
    final json = await _getJson(action: 'get_series');
    return _asMaps(json).map(SeriesItem.fromJson).toList();
  }

  /// Returns the details and episodes of one series.
  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    final json = await _getJson(
      action: 'get_series_info',
      params: {'series_id': '$seriesId'},
    );
    return SeriesInfo.fromJson(json is Map<String, dynamic> ? json : const {});
  }

  /// Returns the details of one movie.
  Future<MovieInfo> getVodInfo(int vodId) async {
    final json = await _getJson(
      action: 'get_vod_info',
      params: {'vod_id': '$vodId'},
    );
    return MovieInfo.fromJson(json is Map<String, dynamic> ? json : const {});
  }

  /// Releases the underlying HTTP connection pool.
  void close() => _http.close();

  /// Performs a GET on `player_api.php` and decodes the JSON body.
  Future<Object?> _getJson({
    String? action,
    Map<String, String> params = const {},
  }) async {
    final uri = playerApiUri(credentials, action: action, params: params);
    final http.Response response;
    try {
      response = await _http
          .get(uri, headers: {'User-Agent': ?userAgent})
          .timeout(_timeout);
    } on TimeoutException {
      throw const XtreamException('El servidor no responde (tiempo agotado).');
    } catch (_) {
      // Network errors embed the URL, so the original message is dropped.
      throw const XtreamException('No se puede conectar con el servidor.');
    }
    if (response.statusCode != 200) {
      throw XtreamException(
        'El servidor ha respondido con un error (HTTP ${response.statusCode}).',
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw const XtreamException(
        'El servidor ha devuelto una respuesta no válida.',
      );
    }
  }

  /// Keeps only the JSON objects of a list response; anything else is empty.
  List<Map<String, dynamic>> _asMaps(Object? json) {
    if (json is! List) return const [];
    return json.whereType<Map<String, dynamic>>().toList();
  }
}
