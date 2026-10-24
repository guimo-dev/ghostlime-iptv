import '../xtream/xtream_urls.dart';

/// What to do when an item with saved progress is opened.
enum ResumePolicy { ask, resume, restart }

/// How video is fitted to the player area.
enum VideoFit { contain, cover, fill }

/// Section shown when the app starts.
enum StartSection { home, live, last }

/// Size of movie and series posters.
enum PosterSize { small, medium, large }

/// Rails of the home screen that can be hidden.
enum HomeRail {
  continueWatching,
  favoriteChannels,
  favoriteMovies,
  favoriteSeries,
  recentChannels,
}

T _enumFrom<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

bool _boolFrom(Object? value, bool fallback) =>
    value is bool ? value : fallback;

String _stringFrom(Object? value, String fallback) =>
    value is String ? value : fallback;

int _intFrom(Object? value, int fallback, int min, int max) =>
    value is num ? value.round().clamp(min, max) : fallback;

/// The allowed refresh interval closest to [value], or 12 when not a number.
int _nearestRefreshHours(Object? value) {
  if (value is! num) return 12;
  const allowed = [6, 12, 24];
  return allowed.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );
}

/// Version written by [AppSettings.toJson]. Settings without it come from
/// versions that hid provider separators by default and saved every field,
/// so their `hideSeparators: true` is taken as that old default and reset
/// once (the next save writes the version, keeping later choices).
const settingsVersion = 2;

/// User settings, immutable. Every field has a default.
class AppSettings {
  const AppSettings({
    this.hardwareDecoding = true,
    this.networkCacheSecs = 10,
    this.autoReconnect = true,
    this.audioLanguage = 'es,spa',
    this.subtitleLanguage = '',
    this.resumePolicy = ResumePolicy.ask,
    this.autoNextEpisode = true,
    this.videoFit = VideoFit.contain,
    this.previewSound = false,
    this.hideSeparators = false,
    this.stripChannelPrefix = false,
    this.defaultLiveFormat = LiveFormat.ts,
    this.startSection = StartSection.home,
    this.openLastPlaylist = false,
    this.lastPlaylistId,
    this.hiddenHomeRails = const {},
    this.posterSize = PosterSize.medium,
    this.epgRefreshHours = 12,
    this.epgOffsetMinutes = 0,
    this.hideAdult = true,
    this.parentalLock = false,
    this.lockedCategories = const {},
  });

  /// Restores settings saved with [toJson]; missing, unknown or invalid values
  /// fall back to defaults and numbers are clamped to their range.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final rails = json['hiddenHomeRails'];
    final locked = json['lockedCategories'];
    final lastPlaylistId = json['lastPlaylistId'];
    final version = json['settingsVersion'];
    final beforeVisibleSeparators = version is! num || version < 2;
    return AppSettings(
      hardwareDecoding: _boolFrom(json['hardwareDecoding'], true),
      networkCacheSecs: _intFrom(json['networkCacheSecs'], 10, 1, 120),
      autoReconnect: _boolFrom(json['autoReconnect'], true),
      audioLanguage: _stringFrom(json['audioLanguage'], 'es,spa'),
      subtitleLanguage: _stringFrom(json['subtitleLanguage'], ''),
      resumePolicy: _enumFrom(
        ResumePolicy.values,
        json['resumePolicy'],
        ResumePolicy.ask,
      ),
      autoNextEpisode: _boolFrom(json['autoNextEpisode'], true),
      videoFit: _enumFrom(VideoFit.values, json['videoFit'], VideoFit.contain),
      previewSound: _boolFrom(json['previewSound'], false),
      hideSeparators:
          !beforeVisibleSeparators && _boolFrom(json['hideSeparators'], false),
      stripChannelPrefix: _boolFrom(json['stripChannelPrefix'], false),
      defaultLiveFormat: _enumFrom(
        LiveFormat.values,
        json['defaultLiveFormat'],
        LiveFormat.ts,
      ),
      startSection: _enumFrom(
        StartSection.values,
        json['startSection'],
        StartSection.home,
      ),
      openLastPlaylist: _boolFrom(json['openLastPlaylist'], false),
      lastPlaylistId: lastPlaylistId is int ? lastPlaylistId : null,
      hiddenHomeRails: rails is List
          ? {
              for (final name in rails)
                for (final rail in HomeRail.values)
                  if (rail.name == name) rail,
            }
          : const {},
      posterSize: _enumFrom(
        PosterSize.values,
        json['posterSize'],
        PosterSize.medium,
      ),
      epgRefreshHours: _nearestRefreshHours(json['epgRefreshHours']),
      epgOffsetMinutes: _intFrom(json['epgOffsetMinutes'], 0, -720, 720),
      hideAdult: _boolFrom(json['hideAdult'], true),
      parentalLock: _boolFrom(json['parentalLock'], false),
      lockedCategories: locked is List
          ? locked.whereType<String>().toSet()
          : const {},
    );
  }

  final bool hardwareDecoding;
  final int networkCacheSecs;
  final bool autoReconnect;
  final String audioLanguage;
  final String subtitleLanguage;
  final ResumePolicy resumePolicy;
  final bool autoNextEpisode;
  final VideoFit videoFit;
  final bool previewSound;
  final bool hideSeparators;
  final bool stripChannelPrefix;
  final LiveFormat defaultLiveFormat;
  final StartSection startSection;
  final bool openLastPlaylist;
  final int? lastPlaylistId;
  final Set<HomeRail> hiddenHomeRails;
  final PosterSize posterSize;
  final int epgRefreshHours;
  final int epgOffsetMinutes;
  final bool hideAdult;
  final bool parentalLock;

  /// Locked categories as `'<playlistId>/<kind>/<categoryId>'`.
  final Set<String> lockedCategories;

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({
    bool? hardwareDecoding,
    int? networkCacheSecs,
    bool? autoReconnect,
    String? audioLanguage,
    String? subtitleLanguage,
    ResumePolicy? resumePolicy,
    bool? autoNextEpisode,
    VideoFit? videoFit,
    bool? previewSound,
    bool? hideSeparators,
    bool? stripChannelPrefix,
    LiveFormat? defaultLiveFormat,
    StartSection? startSection,
    bool? openLastPlaylist,
    int? lastPlaylistId,
    Set<HomeRail>? hiddenHomeRails,
    PosterSize? posterSize,
    int? epgRefreshHours,
    int? epgOffsetMinutes,
    bool? hideAdult,
    bool? parentalLock,
    Set<String>? lockedCategories,
  }) => AppSettings(
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    networkCacheSecs: networkCacheSecs ?? this.networkCacheSecs,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    audioLanguage: audioLanguage ?? this.audioLanguage,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    resumePolicy: resumePolicy ?? this.resumePolicy,
    autoNextEpisode: autoNextEpisode ?? this.autoNextEpisode,
    videoFit: videoFit ?? this.videoFit,
    previewSound: previewSound ?? this.previewSound,
    hideSeparators: hideSeparators ?? this.hideSeparators,
    stripChannelPrefix: stripChannelPrefix ?? this.stripChannelPrefix,
    defaultLiveFormat: defaultLiveFormat ?? this.defaultLiveFormat,
    startSection: startSection ?? this.startSection,
    openLastPlaylist: openLastPlaylist ?? this.openLastPlaylist,
    lastPlaylistId: lastPlaylistId ?? this.lastPlaylistId,
    hiddenHomeRails: hiddenHomeRails ?? this.hiddenHomeRails,
    posterSize: posterSize ?? this.posterSize,
    epgRefreshHours: epgRefreshHours ?? this.epgRefreshHours,
    epgOffsetMinutes: epgOffsetMinutes ?? this.epgOffsetMinutes,
    hideAdult: hideAdult ?? this.hideAdult,
    parentalLock: parentalLock ?? this.parentalLock,
    lockedCategories: lockedCategories ?? this.lockedCategories,
  );

  /// JSON form for storage.
  Map<String, Object?> toJson() => {
    'settingsVersion': settingsVersion,
    'hardwareDecoding': hardwareDecoding,
    'networkCacheSecs': networkCacheSecs,
    'autoReconnect': autoReconnect,
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
    'resumePolicy': resumePolicy.name,
    'autoNextEpisode': autoNextEpisode,
    'videoFit': videoFit.name,
    'previewSound': previewSound,
    'hideSeparators': hideSeparators,
    'stripChannelPrefix': stripChannelPrefix,
    'defaultLiveFormat': defaultLiveFormat.name,
    'startSection': startSection.name,
    'openLastPlaylist': openLastPlaylist,
    'lastPlaylistId': lastPlaylistId,
    'hiddenHomeRails': hiddenHomeRails.map((rail) => rail.name).toList()
      ..sort(),
    'posterSize': posterSize.name,
    'epgRefreshHours': epgRefreshHours,
    'epgOffsetMinutes': epgOffsetMinutes,
    'hideAdult': hideAdult,
    'parentalLock': parentalLock,
    'lockedCategories': lockedCategories.toList()..sort(),
  };
}
