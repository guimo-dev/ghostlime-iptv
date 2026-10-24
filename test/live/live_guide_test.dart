import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/epg/guide_grid.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/sync/account_scope.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/app_theme.dart';

import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';

// Channels without a URL, so selecting one never opens a real player.
const _channels = [
  Channel(
    key: 'a',
    name: 'Uno',
    categoryId: 'c',
    kind: MediaKind.live,
    epgId: 'e1',
  ),
  Channel(key: 'b', name: 'Dos', categoryId: 'c', kind: MediaKind.live),
  Channel(key: 'x', name: 'Otro', categoryId: 'd', kind: MediaKind.live),
];

/// The screen's clock in these tests: local noon of a fixed day, so "the
/// rest of today" never depends on when the test runs.
final _noon = DateTime(2030, 1, 15, 12);

void main() {
  late CatalogDb db;
  late Playlist playlist;

  setUp(() {
    db = CatalogDb.inMemory();
    const unsaved = Playlist(
      name: 'Lista',
      type: PlaylistType.m3uUrl,
      source: 'http://h/l.m3u',
    );
    playlist = unsaved.copyWith(id: db.savePlaylist(unsaved));
    db.replaceCatalog(
      playlist.id!,
      const [
        Category(id: 'c', name: 'Cat', kind: MediaKind.live),
        Category(id: 'd', name: 'Otra', kind: MediaKind.live),
      ],
      _channels,
      DateTime.now(),
    );
    // On air around noon, three more this afternoon and one tomorrow.
    final noon = _noon.toUtc();
    Programme programme(int i, int fromHour) => Programme(
      channelId: 'e1',
      start: noon.add(Duration(hours: fromHour)),
      stop: noon.add(Duration(hours: fromHour + 1)),
      title: 'Programa $i',
    );
    db.replaceEpg(playlist.id!, [
      Programme(
        channelId: 'e1',
        start: noon.subtract(const Duration(hours: 1)),
        stop: noon.add(const Duration(hours: 1)),
        title: 'Programa 0',
      ),
      for (var i = 1; i < 4; i++) programme(i, i),
      programme(4, 14),
    ], DateTime.now());
  });
  tearDown(() => db.close());

  Future<void> pumpLive(WidgetTester tester, {AccountService? account}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccountScope(
        service: account,
        child: SettingsScope(
          controller: SettingsController(db),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: LiveTvScreen(
                db: db,
                playlist: playlist,
                passwords: MemoryPasswordStore(),
                clock: () => _noon,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cat'));
    await tester.pump();
  }

  Finder guideToggle() => find.ancestor(
    of: find.text('Guía'),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  testWidgets('the guide toggle swaps the channel list for the grid', (
    tester,
  ) async {
    await pumpLive(tester);
    expect(find.byType(ChannelRow), findsNWidgets(2));
    expect(find.byType(GuideGrid), findsNothing);

    await tester.tap(guideToggle());
    await tester.pump();

    expect(find.byType(ChannelRow), findsNothing);
    final grid = tester.widget<GuideGrid>(find.byType(GuideGrid));
    expect(grid.channels.map((c) => c.key), ['a', 'b']);

    await tester.tap(guideToggle());
    await tester.pump();
    expect(find.byType(ChannelRow), findsNWidgets(2));
  });

  testWidgets('the toggle is remembered for the playlist', (tester) async {
    await pumpLive(tester);
    await tester.tap(guideToggle());
    await tester.pump();
    expect(db.liveGuideGrid(playlist.id!), isTrue);

    await tester.pumpWidget(const SizedBox());
    await pumpLive(tester);
    expect(find.byType(GuideGrid), findsOneWidget);
  });

  testWidgets('tapping a channel in the grid selects it like the list', (
    tester,
  ) async {
    await pumpLive(tester);
    await tester.tap(guideToggle());
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(GuideGrid), matching: find.text('Dos')),
    );
    await tester.pump();
    expect(
      find.descendant(of: find.byType(NowPanel), matching: find.text('Dos')),
      findsOneWidget,
    );
  });

  testWidgets('the panel lists the rest of today for the selected channel', (
    tester,
  ) async {
    await pumpLive(tester);
    await tester.tap(find.byType(ChannelRow).first);
    await tester.pump();
    final panel = tester.widget<NowPanel>(find.byType(NowPanel));
    expect(panel.now?.title, 'Programa 0');
    expect(panel.upcoming.map((p) => p.title), [
      'Programa 1',
      'Programa 2',
      'Programa 3',
    ]);
    expect(
      find.descendant(
        of: find.byType(NowPanel),
        matching: find.text('A continuación'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a toggle changed by a sync shows up while Live is visible', (
    tester,
  ) async {
    final account = AccountService(
      db: db,
      auth: FakeAuthGateway({}),
      backend: InMemorySyncBackend(),
      keys: FakeKeyStore(),
      passwords: FakePasswords(),
    );
    addTearDown(account.dispose);
    await pumpLive(tester, account: account);
    expect(find.byType(GuideGrid), findsNothing);

    // As a sync applying the pref would: the database changes underneath
    // and the account notifies.
    db.saveLiveGuideGrid(playlist.id!, true);
    await account.setSyncSettings(false);
    await tester.pump();

    expect(find.byType(GuideGrid), findsOneWidget);
  });
}
