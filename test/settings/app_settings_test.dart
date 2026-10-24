import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

void main() {
  test('defaults match the design', () {
    const s = AppSettings();
    expect(s.hardwareDecoding, isTrue);
    expect(s.networkCacheSecs, 10);
    expect(s.autoReconnect, isTrue);
    expect(s.audioLanguage, 'es,spa');
    expect(s.subtitleLanguage, '');
    expect(s.resumePolicy, ResumePolicy.ask);
    expect(s.autoNextEpisode, isTrue);
    expect(s.videoFit, VideoFit.contain);
    expect(s.previewSound, isFalse);
    expect(s.hideSeparators, isFalse);
    expect(s.stripChannelPrefix, isFalse);
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
      audioLanguage: 'en',
      subtitleLanguage: 'es',
      resumePolicy: ResumePolicy.restart,
      autoNextEpisode: false,
      videoFit: VideoFit.cover,
      previewSound: true,
      hideSeparators: true,
      stripChannelPrefix: true,
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
    );
    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expect(restored.hiddenHomeRails, original.hiddenHomeRails);
    expect(restored.lockedCategories, original.lockedCategories);
    expect(restored.lastPlaylistId, 7);
    expect(restored.defaultLiveFormat, LiveFormat.m3u8);
    expect(restored.epgOffsetMinutes, -90);
  });

  test('unknown keys and values fall back to defaults without throwing', () {
    final s = AppSettings.fromJson({
      'mystery': 1,
      'videoFit': 'stretch',
      'resumePolicy': 3,
      'hardwareDecoding': 'yes',
      'audioLanguage': 42,
      'networkCacheSecs': 'ten',
      'lastPlaylistId': 'x',
      'hiddenHomeRails': ['nope', 'favoriteSeries', 5],
      'lockedCategories': 'not a list',
      'defaultLiveFormat': 'dash',
    });
    expect(s.videoFit, VideoFit.contain);
    expect(s.resumePolicy, ResumePolicy.ask);
    expect(s.hardwareDecoding, isTrue);
    expect(s.audioLanguage, 'es,spa');
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

  test('separators show by default', () {
    expect(AppSettings.fromJson(const {}).hideSeparators, isFalse);
  });

  test('settings saved before the separators change show them once', () {
    // Older versions saved every field, so `true` was just their default.
    final old = AppSettings.fromJson(const {
      'hideSeparators': true,
      'audioLanguage': 'en',
    });
    expect(old.hideSeparators, isFalse);
    expect(old.audioLanguage, 'en');
    expect(old.toJson()['settingsVersion'], settingsVersion);
  });

  test('a choice made after the change is kept', () {
    final chosen = const AppSettings(hideSeparators: true).toJson();
    expect(chosen['settingsVersion'], settingsVersion);
    expect(AppSettings.fromJson(chosen).hideSeparators, isTrue);
  });

  test('copyWith replaces only the given fields', () {
    final s = const AppSettings().copyWith(videoFit: VideoFit.fill);
    expect(s.videoFit, VideoFit.fill);
    expect(s.networkCacheSecs, 10);
  });
}
