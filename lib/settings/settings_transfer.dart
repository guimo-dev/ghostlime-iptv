import 'dart:convert';

import 'app_settings.dart';

// Kept as 'iptv-player-settings' so exports made before the rename still import.
const _format = 'iptv-player-settings';

/// Fields that never leave the device: parental control and the last opened
/// playlist (its id only makes sense locally).
const _localOnly = {'parentalLock', 'lockedCategories', 'lastPlaylistId'};

/// Serialises [settings] for a backup file, without parental data.
String exportSettings(AppSettings settings) {
  final json = settings.toJson()..removeWhere((k, _) => _localOnly.contains(k));
  return const JsonEncoder.withIndent('  ')
      .convert({'format': _format, 'settings': json});
}

/// Reads a backup made by [exportSettings] on top of [current].
///
/// Parental control, the last playlist and, while the parental lock is on,
/// "hide adult content" always keep their current values, so a file cannot
/// bypass the PIN. A backup from a build without the accent colour keeps the
/// current one instead of turning it lime. Throws [FormatException] for
/// files that are not backups.
AppSettings importSettings(String text, {required AppSettings current}) {
  final Object? json = jsonDecode(text);
  if (json is! Map<String, Object?> ||
      json['format'] != _format ||
      json['settings'] is! Map<String, Object?>) {
    throw const FormatException('No es una copia de ajustes de esta app.');
  }
  final settings = json['settings']! as Map<String, Object?>;
  final AppSettings imported;
  try {
    imported = AppSettings.fromJson(settings);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Valores no válidos en la copia de ajustes.');
  }
  return imported.copyWith(
    parentalLock: current.parentalLock,
    lockedCategories: current.lockedCategories,
    lastPlaylistId: current.lastPlaylistId,
    hideAdult: current.parentalLock ? current.hideAdult : imported.hideAdult,
    accentColor: settings.containsKey('accentColor')
        ? imported.accentColor
        : current.accentColor,
  );
}
