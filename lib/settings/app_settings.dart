import '../xtream/xtream_urls.dart';

/// What to do when an item with saved progress is opened.
enum ResumePolicy { ask, resume, restart }

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

/// User settings, immutable. Every field has a default.
class AppSettings {
  const AppSettings({
    this.hardwareDecoding = true,
    this.networkCacheSecs = 10,
    this.autoReconnect = true,
    this.resumePolicy = ResumePolicy.ask,
    this.autoNextEpisode = true,
    this.previewSound = false,
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
    this.volumeBrightnessGestures = true,
  });

  /// Restores settings saved with [toJson]; missing, unknown or invalid values
  /// fall back to defaults and numbers are clamped to their range. Keys of
  /// removed options (older saves, syncs and backups) are ignored.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final rails = json['hiddenHomeRails'];
    final locked = json['lockedCategories'];
    final lastPlaylistId = json['lastPlaylistId'];
    return AppSettings(
      hardwareDecoding: _boolFrom(json['hardwareDecoding'], true),
      networkCacheSecs: _intFrom(json['networkCacheSecs'], 10, 1, 120),
      autoReconnect: _boolFrom(json['autoReconnect'], true),
      resumePolicy: _enumFrom(
        ResumePolicy.values,
        json['resumePolicy'],
        ResumePolicy.ask,
      ),
      autoNextEpisode: _boolFrom(json['autoNextEpisode'], true),
      previewSound: _boolFrom(json['previewSound'], false),
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
      volumeBrightnessGestures: _boolFrom(
        json['volumeBrightnessGestures'],
        true,
      ),
    );
  }

  final bool hardwareDecoding;
  final int networkCacheSecs;
  final bool autoReconnect;
  final ResumePolicy resumePolicy;
  final bool autoNextEpisode;
  final bool previewSound;
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

  /// On phones and tablets, vertical swipes in the player set its volume
  /// (right side) and the window brightness (left side).
  final bool volumeBrightnessGestures;

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({
    bool? hardwareDecoding,
    int? networkCacheSecs,
    bool? autoReconnect,
    ResumePolicy? resumePolicy,
    bool? autoNextEpisode,
    bool? previewSound,
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
    bool? volumeBrightnessGestures,
  }) => AppSettings(
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    networkCacheSecs: networkCacheSecs ?? this.networkCacheSecs,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    resumePolicy: resumePolicy ?? this.resumePolicy,
    autoNextEpisode: autoNextEpisode ?? this.autoNextEpisode,
    previewSound: previewSound ?? this.previewSound,
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
    volumeBrightnessGestures:
        volumeBrightnessGestures ?? this.volumeBrightnessGestures,
  );

  /// JSON form for storage.
  Map<String, Object?> toJson() => {
    'hardwareDecoding': hardwareDecoding,
    'networkCacheSecs': networkCacheSecs,
    'autoReconnect': autoReconnect,
    'resumePolicy': resumePolicy.name,
    'autoNextEpisode': autoNextEpisode,
    'previewSound': previewSound,
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
    'volumeBrightnessGestures': volumeBrightnessGestures,
  };
}
