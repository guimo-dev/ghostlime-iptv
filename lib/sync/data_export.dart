import 'dart:convert';

import '../catalog/catalog_db.dart';
import '../settings/app_settings.dart';
import '../settings/settings_transfer.dart';

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
          'server': p.serverUrl,
          'username': p.username,
          'source': p.source,
        },
    ],
    'favorites': [
      for (final f in db.allFavorites())
        {
          'playlist': names[f.playlistId],
          'kind': f.kind.name,
          'key': f.key,
          'addedAt': f.addedAt.toUtc().toIso8601String(),
        },
    ],
    'progress': [
      for (final p in db.allProgress())
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
