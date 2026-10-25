import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/browse/catalog_images.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/guide_grid.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/legal/legal_screen.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/play_target.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/playlists/playlists_screen.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/app_theme.dart';
import 'package:iptv_player/ui/form_factor.dart';
import 'package:iptv_player/ui/ghostlime_logo.dart';
import 'package:iptv_player/vod/movie_detail_screen.dart';
import 'package:iptv_player/vod/series_detail_screen.dart';
import 'package:iptv_player/welcome/welcome_screen.dart';

import '../../tool/demo_server/demo_data.dart';
import '../player/fake_player.dart';
import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';

/// Phones in portrait and landscape and a portrait tablet: none of them gets
/// the desktop layout.
const _sizes = [
  Size(360, 640),
  Size(390, 844),
  Size(412, 915),
  Size(640, 360),
  Size(844, 390),
  Size(768, 1024),
];

/// Screens with the height of their on-screen keyboard: phones upright, a
/// portrait tablet and a phone on its side (a shorter keyboard).
const _keyboards = [
  (Size(360, 640), 300.0),
  (Size(390, 844), 300.0),
  (Size(412, 915), 300.0),
  (Size(768, 1024), 400.0),
  (Size(640, 360), 180.0),
];

/// The demo catalog in a fresh database, as an M3U playlist (no network).
class _Demo {
  _Demo() {
    final id = db.savePlaylist(
      const Playlist(
        name: 'Lista demo',
        type: PlaylistType.m3uUrl,
        source: 'http://demo.invalid/get.php',
      ),
    );
    playlist = db.playlists().firstWhere((p) => p.id == id);
    db.replaceCatalog(
      id,
      [
        for (final MapEntry(:key, :value) in liveCategoryNames.entries)
          Category(id: key, name: value, kind: MediaKind.live),
        for (final MapEntry(:key, :value) in movieCategoryNames.entries)
          Category(id: key, name: value, kind: MediaKind.movie),
        for (final MapEntry(:key, :value) in seriesCategoryNames.entries)
          Category(id: key, name: value, kind: MediaKind.series),
      ],
      [...liveChannels, ...movies, ...episodes],
      DateTime.now(),
    );
    final now = DateTime.now();
    db.replaceEpg(id, [
      for (final p in demoProgrammes(now))
        Programme(
          channelId: p.channelId,
          start: p.start,
          stop: p.stop,
          title: p.title,
        ),
    ], now);
    db.setFavorite(id, MediaKind.live, liveChannels.first.key, true);
    db.setFavorite(id, MediaKind.movie, movies.first.key, true);
    db.addRecent(id, MediaKind.live, liveChannels[1].key);
    db.saveProgress(
      id,
      PlayTarget.fromChannel(movies.first),
      const Duration(minutes: 40),
      const Duration(minutes: 100),
    );
  }

  final db = CatalogDb.inMemory();
  late final Playlist playlist;

  final liveChannels = [
    for (final c in demoChannels)
      Channel(
        key: 'live-${c.id}',
        name: c.name,
        categoryId: c.categoryId,
        kind: MediaKind.live,
        epgId: c.epgId,
        url: 'http://demo.invalid/live/${c.id}.ts',
      ),
  ];

  final movies = [
    for (final m in demoMovies)
      Channel(
        key: 'movie-${m.id}',
        name: m.title,
        categoryId: m.categoryId,
        kind: MediaKind.movie,
        url: 'http://demo.invalid/movie/${m.id}.mp4',
        rating: 7.5,
      ),
  ];

  final episodes = [
    for (final s in demoSeries)
      for (final e in s.episodes)
        Channel(
          key: 'episode-${e.id}',
          name: '${s.title} S0${e.season}E0${e.number}',
          categoryId: s.categoryId,
          kind: MediaKind.series,
          url: 'http://demo.invalid/series/${e.id}.mp4',
        ),
  ];

  /// Episodes of the first demo show, as the series page gets them.
  List<Channel> get firstShow =>
      episodes.where((e) => e.name.startsWith(demoSeries.first.title)).toList();
}

/// Sets the test screen to [size] at 1 logical pixel per pixel.
void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps [home] in the app theme and settings on [db].
Future<void> _pumpApp(WidgetTester tester, CatalogDb db, Widget home) async {
  await tester.pumpWidget(
    SettingsScope(
      controller: SettingsController(db),
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Drags every vertical scrollable on screen to its end, a page at a time,
/// so lazily built rows are laid out too, and checks nothing overflowed.
Future<void> _scrollThrough(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final scrollables = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final scrollable = scrollables.at(i);
    for (var page = 0; page < 40; page++) {
      final state = tester.state<ScrollableState>(scrollable);
      final position = state.position;
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  }
}

/// Opens the bottom bar destination labelled [label].
Future<void> _openSection(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late _Demo demo;
  setUp(() => demo = _Demo());
  tearDown(() => demo.db.close());

  Widget shell() => AppShell(
    db: demo.db,
    playlist: demo.playlist,
    passwords: MemoryPasswordStore(),
  );

  for (final size in _sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('Inicio fits at $at', (tester) async {
      _setSize(tester, size);
      await _pumpApp(tester, demo.db, shell());
      await _scrollThrough(tester);
    });

    for (final section in ['Películas', 'Series']) {
      testWidgets('$section fits at $at', (tester) async {
        _setSize(tester, size);
        await _pumpApp(tester, demo.db, shell());
        await _openSection(tester, section);
        await _scrollThrough(tester);
      });
    }

    testWidgets('Más sheet fits at $at', (tester) async {
      _setSize(tester, size);
      await _pumpApp(tester, demo.db, shell());
      await _openSection(tester, 'Más');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final guide in [false, true]) {
      testWidgets('Directo${guide ? ' with the guide grid' : ''} fits at $at', (
        tester,
      ) async {
        _setSize(tester, size);
        demo.db.saveLiveGuideGrid(demo.playlist.id!, guide);
        final player = FakePlayer();
        await _pumpApp(
          tester,
          demo.db,
          Scaffold(
            body: LiveTvScreen(
              db: demo.db,
              playlist: demo.playlist,
              passwords: MemoryPasswordStore(),
              createPlayer: (_) => (player, FakeVideoController(player)),
            ),
          ),
        );
        if (guide) expect(find.byType(GuideGrid), findsOneWidget);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('movie page fits at $at', (tester) async {
      _setSize(tester, size);
      await _pumpApp(
        tester,
        demo.db,
        MovieDetailScreen(
          db: demo.db,
          playlist: demo.playlist,
          passwords: MemoryPasswordStore(),
          movie: demo.movies.first,
        ),
      );
      await _scrollThrough(tester);
    });

    testWidgets('series page fits at $at', (tester) async {
      _setSize(tester, size);
      await _pumpApp(
        tester,
        demo.db,
        SeriesDetailScreen(
          db: demo.db,
          playlist: demo.playlist,
          passwords: MemoryPasswordStore(),
          series: Channel(
            key: 'show',
            name: demoSeries.first.title,
            categoryId: demoSeries.first.categoryId,
            kind: MediaKind.series,
          ),
          m3uEpisodes: demo.firstShow,
        ),
      );
      await _scrollThrough(tester);
    });

    testWidgets('Listas fits at $at', (tester) async {
      _setSize(tester, size);
      await _pumpApp(
        tester,
        demo.db,
        PlaylistsScreen(db: demo.db, passwords: MemoryPasswordStore()),
      );
      await _scrollThrough(tester);
    });

    for (final type in ['Xtream', 'M3U (URL)', 'M3U (fichero)']) {
      testWidgets('$type form fits at $at', (tester) async {
        _setSize(tester, size);
        await _pumpApp(tester, demo.db, const PlaylistFormScreen());
        await tester.tap(find.text(type));
        await tester.pumpAndSettle();
        await _scrollThrough(tester);
      });
    }

    testWidgets('Ajustes fits at $at', (tester) async {
      _setSize(tester, size);
      await _pumpApp(
        tester,
        demo.db,
        SettingsScreen(
          db: demo.db,
          passwords: FakePasswords(),
          playlist: demo.playlist,
        ),
      );
      await _scrollThrough(tester);
    });

    testWidgets('Bienvenida fits at $at', (tester) async {
      _setSize(tester, size);
      final account = AccountService(
        db: demo.db,
        auth: FakeAuthGateway({}),
        backend: InMemorySyncBackend(),
        keys: FakeKeyStore(),
        passwords: FakePasswords(),
      );
      addTearDown(account.dispose);
      await _pumpApp(
        tester,
        demo.db,
        WelcomeScreen(account: account, onDone: () {}),
      );
      await _scrollThrough(tester);
    });

    testWidgets('Términos de uso fits at $at', (tester) async {
      _setSize(tester, size);
      // Load the asset outside the fake clock, then show it from the cache.
      await tester.runAsync(() => loadLegalText(LegalDoc.terms));
      await _pumpApp(tester, demo.db, const LegalScreen(doc: LegalDoc.terms));
      await _scrollThrough(tester);
    });
  }

  for (final (size, keyboard) in _keyboards) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('the keyboard leaves the focused form field visible at $at', (
      tester,
    ) async {
      _setSize(tester, size);
      await _pumpApp(tester, demo.db, const PlaylistFormScreen());
      await tester.tap(find.text('Xtream'));
      await tester.pumpAndSettle();
      // The lowest field fully shown (above the bottom action bar): the
      // keyboard will cover it.
      final viewport = find.byType(SingleChildScrollView);
      final fields = find.byType(TextFormField);
      final onScreen = [
        for (var i = 0; i < fields.evaluate().length; i++)
          if (tester.getRect(fields.at(i)).bottom <=
              tester.getRect(viewport).bottom)
            i,
      ];
      final target = fields.at(onScreen.last);
      final keyboardTop = size.height - keyboard;
      expect(tester.getRect(target).bottom, greaterThan(keyboardTop));
      await tester.tap(target);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final field = tester.getRect(target);
      // The app bar stays on top: the field must show below it.
      expect(field.top, greaterThanOrEqualTo(kToolbarHeight));
      expect(field.bottom, lessThanOrEqualTo(keyboardTop));
      // Nor hidden behind the action bar, which rides above the keyboard.
      expect(field.bottom, lessThanOrEqualTo(tester.getRect(viewport).bottom));
    });
  }

  // A phone and a landscape tablet (desktop layout, side bar).
  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('nothing in the shell sits under the status bar at $at', (
      tester,
    ) async {
      const statusBar = 24.0;
      _setSize(tester, size);
      tester.view.padding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.resetPadding);
      await _pumpApp(tester, demo.db, shell());

      final drawn = [
        ...find.byType(Text).evaluate(),
        ...find.byType(Icon).evaluate(),
        ...find.byType(GhostlimeLogo).evaluate(),
      ];
      expect(drawn, isNotEmpty);
      for (final element in drawn) {
        final top = (element.renderObject! as RenderBox)
            .localToGlobal(Offset.zero)
            .dy;
        expect(top, greaterThanOrEqualTo(statusBar), reason: '$element');
      }
    });
  }

  const phone = Size(360, 640);

  testWidgets('the movie grid has two columns within 16 px margins', (
    tester,
  ) async {
    _setSize(tester, phone);
    // Without progress the section opens on its first category.
    demo.db.clearAllProgress();
    await _pumpApp(tester, demo.db, shell());
    await _openSection(tester, 'Películas');
    // Each tile is a column: poster (scaled down at rest), then the title.
    Rect tile(int index) => tester.getRect(
      find
          .ancestor(
            of: find.byType(Poster).at(index),
            matching: find.byType(Column),
          )
          .first,
    );
    final first = tile(0);
    final second = tile(1);
    expect(second.top, closeTo(first.top, 0.5));
    expect(first.left, closeTo(phonePageMargin, 0.5));
    expect(second.right, closeTo(phone.width - phonePageMargin, 0.5));
  });

  testWidgets('the movie page puts the poster above the title', (tester) async {
    _setSize(tester, phone);
    await _pumpApp(
      tester,
      demo.db,
      MovieDetailScreen(
        db: demo.db,
        playlist: demo.playlist,
        passwords: MemoryPasswordStore(),
        movie: demo.movies.first,
      ),
    );
    final poster = tester.getRect(find.byType(Poster));
    final title = tester.getRect(find.text(demo.movies.first.name));
    expect(title.top, greaterThanOrEqualTo(poster.bottom));
    expect(poster.center.dx, closeTo(phone.width / 2, 0.5));
  });

  testWidgets('settings sections take the full width with 16 px margins', (
    tester,
  ) async {
    _setSize(tester, phone);
    await _pumpApp(
      tester,
      demo.db,
      SettingsScreen(
        db: demo.db,
        passwords: FakePasswords(),
        playlist: demo.playlist,
      ),
    );
    final section = tester.getRect(
      find
          .ancestor(
            of: find.text('Búfer de red'),
            matching: find.byType(Container),
          )
          .last,
    );
    expect(section.left, closeTo(phonePageMargin, 0.5));
    expect(section.right, closeTo(phone.width - phonePageMargin, 0.5));
  });
}
