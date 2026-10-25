import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

void main() {
  test('defaults match the design', () {
    const s = AppSettings();
    expect(s.hardwareDecoding, isTrue);
    expect(s.networkCacheSecs, 10);
    expect(s.autoReconnect, isTrue);
    expect(s.resumePolicy, ResumePolicy.ask);
    expect(s.autoNextEpisode, isTrue);
    expect(s.previewSound, isFalse);
    expect(s.defaultLiveFormat, LiveFormat.ts);
    expect(s.startSection, StartSection.home);
    expect(s.openLastPlaylist, isFalse);
    expect(s.lastPlaylistId, isNull);
    expect(s.hiddenHomeRails, isEmpty);
    expect(s.posterSize, PosterSize.medium);
    expect(s.epgRefreshHours, 12);
    expect(s.epgOffsetMinutes, 0);
    expect(s.hideAdult, isTrue);
    expect(s.parentalLock, isFalse);
    expect(s.lockedCategories, isEmpty);
    expect(s.volumeBrightnessGestures, isTrue);
    expect(s.accentColor, AccentColor.lime);
  });

  test('fromJson of an empty map gives the defaults', () {
    final json = AppSettings.fromJson(const {}).toJson();
    expect(json, isNotEmpty);
    expect(json, const AppSettings().toJson());
  });

  test('round-trips every field through toJson and fromJson', () {
    const original = AppSettings(
      hardwareDecoding: false,
      networkCacheSecs: 45,
      autoReconnect: false,
      resumePolicy: ResumePolicy.restart,
      autoNextEpisode: false,
      previewSound: true,
      defaultLiveFormat: LiveFormat.m3u8,
      startSection: StartSection.last,
      openLastPlaylist: true,
      lastPlaylistId: 7,
      hiddenHomeRails: {HomeRail.favoriteMovies, HomeRail.recentChannels},
      posterSize: PosterSize.large,
      epgRefreshHours: 24,
      epgOffsetMinutes: -90,
      hideAdult: false,
      parentalLock: true,
      lockedCategories: {'1/live/5', '2/movie/9'},
      volumeBrightnessGestures: false,
      accentColor: AccentColor.violet,
    );
    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expect(restored.hiddenHomeRails, original.hiddenHomeRails);
    expect(restored.lockedCategories, original.lockedCategories);
    expect(restored.lastPlaylistId, 7);
    expect(restored.defaultLiveFormat, LiveFormat.m3u8);
    expect(restored.epgOffsetMinutes, -90);
    expect(restored.volumeBrightnessGestures, isFalse);
    expect(restored.accentColor, AccentColor.violet);
  });

  test("an accent colour from another version falls back to lime", () {
    expect(
      AppSettings.fromJson(const {"accentColor": "teal"}).accentColor,
      AccentColor.lime,
    );
    expect(
      AppSettings.fromJson(const {"accentColor": 3}).accentColor,
      AccentColor.lime,
    );
  });

  test('unknown keys and values fall back to defaults without throwing', () {
    final s = AppSettings.fromJson({
      'mystery': 1,
      'posterSize': 'huge',
      'resumePolicy': 3,
      'hardwareDecoding': 'yes',
      'autoReconnect': 42,
      'networkCacheSecs': 'ten',
      'lastPlaylistId': 'x',
      'hiddenHomeRails': ['nope', 'favoriteSeries', 5],
      'lockedCategories': 'not a list',
      'defaultLiveFormat': 'dash',
    });
    expect(s.posterSize, PosterSize.medium);
    expect(s.resumePolicy, ResumePolicy.ask);
    expect(s.hardwareDecoding, isTrue);
    expect(s.autoReconnect, isTrue);
    expect(s.networkCacheSecs, 10);
    expect(s.lastPlaylistId, isNull);
    expect(s.hiddenHomeRails, {HomeRail.favoriteSeries});
    expect(s.lockedCategories, isEmpty);
    expect(s.defaultLiveFormat, LiveFormat.ts);
  });

  test('out-of-range numbers are clamped', () {
    expect(AppSettings.fromJson({'networkCacheSecs': 0}).networkCacheSecs, 1);
    expect(
      AppSettings.fromJson({'networkCacheSecs': 999}).networkCacheSecs,
      120,
    );
    expect(
      AppSettings.fromJson({'epgOffsetMinutes': -5000}).epgOffsetMinutes,
      -720,
    );
    expect(
      AppSettings.fromJson({'epgOffsetMinutes': 5000}).epgOffsetMinutes,
      720,
    );
    expect(AppSettings.fromJson({'epgRefreshHours': 7}).epgRefreshHours, 6);
    expect(AppSettings.fromJson({'epgRefreshHours': 100}).epgRefreshHours, 24);
    expect(AppSettings.fromJson({'epgRefreshHours': 0}).epgRefreshHours, 6);
  });

  test('settings saved with removed options still load, without them', () {
    final old = AppSettings.fromJson(const {
      'settingsVersion': 2,
      'audioLanguage': 'en',
      'subtitleLanguage': 'es',
      'videoFit': 'cover',
      'hideSeparators': true,
      'stripChannelPrefix': true,
      'networkCacheSecs': 30,
    });
    expect(old.networkCacheSecs, 30);
    expect(old.toJson().keys, isNot(contains('settingsVersion')));
    for (final removed in [
      'audioLanguage',
      'subtitleLanguage',
      'videoFit',
      'hideSeparators',
      'stripChannelPrefix',
    ]) {
      expect(old.toJson().keys, isNot(contains(removed)));
    }
  });

  test('copyWith replaces only the given fields', () {
    final s = const AppSettings().copyWith(posterSize: PosterSize.large);
    expect(s.posterSize, PosterSize.large);
    expect(s.networkCacheSecs, 10);
  });
}
