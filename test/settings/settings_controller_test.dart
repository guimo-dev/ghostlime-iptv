import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late CatalogDb db;
  setUp(() => db = CatalogDb.inMemory());
  tearDown(() => db.close());

  test('starts with defaults on an empty database', () {
    final value = SettingsController(db).value;
    expect(value.toJson(), isNotEmpty);
    expect(value.toJson(), const AppSettings().toJson());
  });

  test('update persists and a new controller loads it', () {
    SettingsController(db).update(
      const AppSettings(posterSize: PosterSize.large, networkCacheSecs: 60),
    );
    final loaded = SettingsController(db).value;
    expect(loaded.posterSize, PosterSize.large);
    expect(loaded.networkCacheSecs, 60);
  });

  test('update changes value, notifies, and skips unchanged updates', () {
    final controller = SettingsController(db);
    var calls = 0;
    controller.addListener(() => calls++);
    controller.update(const AppSettings(hideAdult: false));
    expect(controller.value.hideAdult, isFalse);
    expect(calls, 1);
    controller.update(const AppSettings(hideAdult: false));
    expect(calls, 1);
    controller.update(const AppSettings());
    expect(calls, 2);
  });

  test('saveSettings and loadSettings round-trip a map', () {
    db.saveSettings({'a': 1, 'b': 'x'});
    expect(db.loadSettings(), {'a': 1, 'b': 'x'});
  });

  test('loadSettings is empty when nothing was saved', () {
    expect(db.loadSettings(), isEmpty);
  });

  test('corrupt stored JSON loads as defaults without throwing', () {
    final dir = Directory.systemTemp.createTempSync('settings_test');
    final path = '${dir.path}/catalog.db';
    try {
      CatalogDb.open(path).close();
      final raw = sqlite3.open(path);
      raw.execute(
        "INSERT INTO prefs (playlist_id, scope, value) "
        "VALUES (0, 'settings', '{broken')",
      );
      raw.close();
      final reopened = CatalogDb.open(path);
      expect(reopened.loadSettings(), isEmpty);
      final value = SettingsController(reopened).value;
      expect(value.toJson(), isNotEmpty);
      expect(value.toJson(), const AppSettings().toJson());
      reopened.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('stored JSON that is not an object loads as empty', () {
    final dir = Directory.systemTemp.createTempSync('settings_test');
    final path = '${dir.path}/catalog.db';
    try {
      CatalogDb.open(path).close();
      final raw = sqlite3.open(path);
      raw.execute(
        "INSERT INTO prefs (playlist_id, scope, value) "
        "VALUES (0, 'settings', '[1,2]')",
      );
      raw.close();
      final reopened = CatalogDb.open(path);
      expect(reopened.loadSettings(), isEmpty);
      reopened.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
