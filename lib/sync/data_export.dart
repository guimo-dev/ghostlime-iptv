import 'dart:convert';

import '../catalog/catalog_db.dart';
import '../settings/app_settings.dart';
import '../playlists/playlist.dart';
import '../settings/settings_transfer.dart';

/// [serverUrl] without userinfo (`user:pass@`); `null` when it is not a URL.
String? _withoutUserInfo(String? serverUrl) {
  final uri = serverUrl == null ? null : Uri.tryParse(serverUrl);
  if (uri == null || !uri.hasAuthority) return null;
  return uri.replace(userInfo: '').toString().replaceFirst('//@', '//');
}

/// The part of a playlist source that is safe to share: `scheme://host[:port]`
/// for an M3U URL (path and query may carry credentials), the file name for a
/// local file, nothing for Xtream.
String? _safeSource(Playlist playlist) {
  final source = playlist.source;
  if (source == null) return null;
  switch (playlist.type) {
    case PlaylistType.m3uUrl:
      final uri = Uri.tryParse(source);
      if (uri == null || !uri.hasAuthority) return null;
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    case PlaylistType.m3uFile:
      return source.split(RegExp(r'[\\/]')).last;
    case PlaylistType.xtream:
      return null;
  }
}

/// Everything the app keeps about the user on this device, as a JSON-ready map
/// for "Exportar mis datos": playlists, favorites, progress and settings.
///
/// It never includes playlist passwords (they live in the secure storage and
/// this function cannot reach them), the parental PIN or the locked
/// categories. Favorites and progress name their playlist instead of using
/// local ids.
Map<String, Object?> exportUserData(CatalogDb db, AppSettings settings) {
  final playlists = db.playlists();
  final names = {for (final p in playlists) p.id!: p.name};
  return {
    'format': 'ghostlime-export',
    'version': 1,
    'playlists': [
      for (final p in playlists)
        {
          'name': p.name,
          'type': p.type.name,
          'server': _withoutUserInfo(p.serverUrl),
          'username': p.username,
          'source': _safeSource(p),
        },
    ],
    'favorites': [
      for (final f in db.allFavorites())
        if (names.containsKey(f.playlistId))
          {
            'playlist': names[f.playlistId],
            'kind': f.kind.name,
            'key': f.key,
            'addedAt': f.addedAt.toUtc().toIso8601String(),
          },
    ],
    'progress': [
      for (final p in db.allProgress())
        if (names.containsKey(p.playlistId))
          {
            'playlist': names[p.playlistId],
            'kind': p.progress.target.kind.name,
            'key': p.progress.target.key,
            'title': p.progress.target.title,
            'positionMs': p.progress.position.inMilliseconds,
            'durationMs': p.progress.duration.inMilliseconds,
            'updatedAt': p.progress.updatedAt.toUtc().toIso8601String(),
          },
    ],
    'settings': (jsonDecode(
      exportSettings(settings),
    ) as Map<String, Object?>)['settings'],
  };
}

/// [exportUserData] as indented JSON text, ready to save to a file.
String exportUserDataJson(CatalogDb db, AppSettings settings) =>
    const JsonEncoder.withIndent('  ').convert(exportUserData(db, settings));
