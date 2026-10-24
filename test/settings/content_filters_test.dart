import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/app_settings.dart';
import 'package:iptv_player/settings/content_filters.dart';
import 'package:iptv_player/xtream/xtream_models.dart';

Category _category(String name, {String id = '5'}) =>
    Category(id: id, name: name, kind: MediaKind.live);

bool _visible(
  AppSettings settings,
  Category category, {
  bool unlocked = false,
}) => isCategoryVisible(
  settings: settings,
  unlocked: unlocked,
  playlistId: 1,
  kind: MediaKind.live,
  category: category,
);

void main() {
  test('isAdultCategory matches adult names as whole words', () {
    for (final name in [
      'Night Adults',
      'CINE | ADULT HD',
      'XXX - Noche HD',
      'Adultos',
      '+18 canales',
      '18+',
      'Porn HD',
    ]) {
      expect(isAdultCategory(name), isTrue, reason: name);
    }
  });

  test('isAdultCategory ignores unrelated names', () {
    for (final name in [
      'Deportes',
      'Sexto sentido',
      'Documentales',
      'Cine',
      '',
    ]) {
      expect(isAdultCategory(name), isFalse, reason: name);
    }
  });

  test('adult categories are hidden only when hideAdult is on', () {
    final adult = _category('XXX Night');
    expect(_visible(const AppSettings(), adult), isFalse);
    expect(_visible(const AppSettings(hideAdult: false), adult), isTrue);
    expect(_visible(const AppSettings(), _category('Cine')), isTrue);
  });

  test('locked categories are hidden until unlocked', () {
    const settings = AppSettings(
      parentalLock: true,
      lockedCategories: {'1/live/5'},
    );
    final category = _category('Cine');
    expect(_visible(settings, category), isFalse);
    expect(_visible(settings, category, unlocked: true), isTrue);
    expect(_visible(settings, _category('Cine', id: '6')), isTrue);
  });

  test('locked entries are ignored while the parental lock is off', () {
    const settings = AppSettings(lockedCategories: {'1/live/5'});
    expect(_visible(settings, _category('Cine')), isTrue);
  });

  test('the lock key includes playlist and kind', () {
    const settings = AppSettings(
      parentalLock: true,
      lockedCategories: {'1/live/5'},
    );
    final movie = Category(id: '5', name: 'Cine', kind: MediaKind.movie);
    expect(
      isCategoryVisible(
        settings: settings,
        unlocked: false,
        playlistId: 1,
        kind: MediaKind.movie,
        category: movie,
      ),
      isTrue,
    );
    expect(
      isCategoryVisible(
        settings: settings,
        unlocked: false,
        playlistId: 2,
        kind: MediaKind.live,
        category: _category('Cine'),
      ),
      isTrue,
    );
    expect(_visible(settings, _category('Cine')), isFalse);
  });

  test('unlocking does not reveal adult categories', () {
    expect(
      _visible(const AppSettings(), _category('XXX'), unlocked: true),
      isFalse,
    );
  });

  test('hiddenCategoryIds lists only the categories that are not visible', () {
    final hidden = hiddenCategoryIds(
      settings: const AppSettings(),
      unlocked: false,
      playlistId: 1,
      kind: MediaKind.live,
      categories: [
        _category('Cine', id: '1'),
        _category('XXX', id: '2'),
      ],
    );
    expect(hidden, {'2'});
  });

  _visibleProgressTests();
}

void _visibleProgressTests() {
  group('visibleProgress', () {
    const total = Duration(minutes: 100);
    const normal = Channel(
      key: 'xm:1',
      name: 'Dune',
      categoryId: 'movie:1',
      kind: MediaKind.movie,
      streamId: 1,
    );
    const adult = Channel(
      key: 'xm:2',
      name: 'Night',
      categoryId: 'movie:2',
      kind: MediaKind.movie,
      streamId: 2,
    );
    late CatalogDb db;
    late int playlistId;

    setUp(() {
      db = CatalogDb.inMemory();
      playlistId = db.savePlaylist(
        const Playlist(
          name: 'X',
          type: PlaylistType.xtream,
          serverUrl: 'http://h',
          username: 'u',
        ),
      );
      db.replaceCatalog(
        playlistId,
        const [
          Category(id: 'movie:1', name: 'Cine', kind: MediaKind.movie),
          Category(id: 'movie:2', name: 'XXX', kind: MediaKind.movie),
        ],
        const [normal, adult],
        DateTime.utc(2026, 10, 20),
      );
      for (final channel in [normal, adult]) {
        db.saveProgress(
          playlistId,
          PlayTarget.fromChannel(channel),
          const Duration(minutes: 50),
          total,
        );
      }
    });
    tearDown(() => db.close());

    test('drops items of hidden categories and keeps the rest', () {
      final shown = visibleProgress(
        db.continueWatching(playlistId, MediaKind.movie),
        db,
        playlistId,
        {'movie:2'},
      );
      expect(shown.map((p) => p.target.key), ['xm:1']);
    });

    test('keeps items that are not in the catalog', () {
      db.saveProgress(
        playlistId,
        PlayTarget.fromChannel(
          const Channel(
            key: 'xm:3',
            name: 'Gone',
            categoryId: 'movie:2',
            kind: MediaKind.movie,
            streamId: 3,
          ),
        ),
        const Duration(minutes: 50),
        total,
      );
      final shown = visibleProgress(
        db.continueWatching(playlistId, MediaKind.movie),
        db,
        playlistId,
        {'movie:2'},
      );
      expect(shown.map((p) => p.target.key), containsAll(['xm:1', 'xm:3']));
      expect(shown, hasLength(2));
    });

    test('resolves an episode through its series', () {
      const series = Channel(
        key: 'xs:5',
        name: 'Dark',
        categoryId: 'series:1',
        kind: MediaKind.series,
        streamId: 5,
      );
      db.replaceCatalog(
        playlistId,
        const [Category(id: 'series:1', name: 'Adult', kind: MediaKind.series)],
        const [series],
        DateTime.utc(2026, 10, 20),
      );
      db.saveProgress(
        playlistId,
        PlayTarget.episode(
          series: series,
          episode: const Episode(
            id: 77,
            season: 1,
            number: 1,
            title: 'A',
            extension: 'mp4',
          ),
        ),
        const Duration(minutes: 20),
        total,
      );
      final items = db.continueWatching(playlistId, MediaKind.series);
      expect(visibleProgress(items, db, playlistId, {'series:1'}), isEmpty);
      expect(visibleProgress(items, db, playlistId, {}), hasLength(1));
    });
  });
}
