import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/settings_transfer.dart';

void main() {
  const locked = AppSettings(
    parentalLock: true,
    lockedCategories: {'1/live/x'},
    lastPlaylistId: 1,
    networkCacheSecs: 30,
  );

  test('export leaves out parental data and the last playlist', () {
    final text = exportSettings(locked);
    final json = jsonDecode(text) as Map<String, Object?>;
    expect(json['format'], 'iptv-player-settings');
    final settings = json['settings'] as Map<String, Object?>;
    expect(settings.containsKey('parentalLock'), isFalse);
    expect(settings.containsKey('lockedCategories'), isFalse);
    expect(settings.containsKey('lastPlaylistId'), isFalse);
    expect(settings['networkCacheSecs'], 30);
  });

  test('import keeps the current parental lock and last playlist', () {
    final text = jsonEncode({
      'format': 'iptv-player-settings',
      'settings': {
        'networkCacheSecs': 5,
        'parentalLock': false,
        'lockedCategories': <String>[],
        'hideAdult': false,
      },
    });
    final result = importSettings(text, current: locked);
    expect(result.networkCacheSecs, 5);
    expect(result.parentalLock, isTrue);
    expect(result.lockedCategories, {'1/live/x'});
    expect(result.lastPlaylistId, 1);
  });

  test('import cannot turn hideAdult off while the parental lock is on', () {
    final text = jsonEncode({
      'format': 'iptv-player-settings',
      'settings': {'hideAdult': false},
    });
    expect(importSettings(text, current: locked).hideAdult, isTrue);
  });

  test('import rejects foreign or broken files', () {
    expect(
      () => importSettings('not json', current: locked),
      throwsFormatException,
    );
    expect(
      () => importSettings(jsonEncode({'a': 1}), current: locked),
      throwsFormatException,
    );
  });

  test('import turns non-finite numbers into a FormatException', () {
    const text =
        '{"format": "iptv-player-settings", '
        '"settings": {"networkCacheSecs": 1e999}}';
    expect(() => importSettings(text, current: locked), throwsFormatException);
  });

  test("the accent colour travels through export and import", () {
    final text = exportSettings(
      const AppSettings(accentColor: AccentColor.orange),
    );
    final settings =
        (jsonDecode(text) as Map<String, Object?>)["settings"]
            as Map<String, Object?>;
    expect(settings["accentColor"], "orange");
    expect(
      importSettings(text, current: const AppSettings()).accentColor,
      AccentColor.orange,
    );
  });
}
