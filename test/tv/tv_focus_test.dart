import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/sorting.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/live/reorder_screen.dart';
import 'package:iptv_player/live/sort_sheet.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/pin_dialog.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_screen.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/tv/exit_dialog.dart';
import 'package:iptv_player/vod/movie_detail_screen.dart';
import 'package:iptv_player/vod/series_detail_screen.dart';
import 'package:iptv_player/welcome/welcome_screen.dart';

import '../player/fake_player.dart';
import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';
import 'tv_harness.dart';

/// Pumps the whole app on [db], as `main` does.
Future<void> _pumpIptvApp(WidgetTester tester, CatalogDb db) async {
  await tester.pumpWidget(
    IptvApp(
      db: db,
      passwords: MemoryPasswordStore(),
      settings: SettingsController(db),
      pins: MemoryPinStore(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Marks the first run as done, so the app opens on Listas.
void _skipFirstRun(CatalogDb db) {
  db.saveWelcomeDone();
  db.saveAcceptedTermsVersion(termsVersion);
}

/// A page with one button that runs [open] with its context: the way to
/// show sheets and dialogs over something.
Widget _opener(void Function(BuildContext context) open) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('abrir'),
      ),
    ),
  ),
);

/// Opens what the `abrir` button of [_opener] shows.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late TvDemo demo;
  setUp(() => demo = TvDemo());
  tearDown(() => demo.db.close());

  testWidgets('welcome: the legal notice and then the welcome', (tester) async {
    useTvView(tester);
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    await _pumpIptvApp(tester, db);
    expect(find.text('Aceptar'), findsOneWidget);
    await expectFocusAndArrows(tester, dialog: true);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    // Its only option, so there is nowhere to move to.
    expect(find.text('Continuar sin cuenta'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == focusedNode().context),
        matching: find.widgetWithText(FilledButton, 'Continuar sin cuenta'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('welcome with an account', (tester) async {
    useTvView(tester);
    final account = AccountService(
      db: demo.db,
      auth: FakeAuthGateway({}),
      backend: InMemorySyncBackend(),
      keys: FakeKeyStore(),
      passwords: FakePasswords(),
      pins: MemoryPinStore(),
    );
    addTearDown(account.dispose);
    await pumpTvApp(
      tester,
      demo.db,
      WelcomeScreen(account: account, termsAccepted: true, onDone: () {}),
    );
    await tester.pumpAndSettle();
    await expectFocusAndArrows(tester);

    await tester.tap(find.text('Entrar con email'));
    await tester.pumpAndSettle();
    await expectFocusAndArrows(tester, dialog: true);
  });

  testWidgets('Listas with playlists', (tester) async {
    useTvView(tester);
    _skipFirstRun(demo.db);
    await _pumpIptvApp(tester, demo.db);
    expect(find.text('Lista demo'), findsOneWidget);
    await expectFocusAndArrows(tester);
  });

  testWidgets('Listas without playlists', (tester) async {
    useTvView(tester);
    final db = CatalogDb.inMemory();
    addTearDown(db.close);
    _skipFirstRun(db);
    await _pumpIptvApp(tester, db);
    expect(find.text('Añade tu primera lista'), findsOneWidget);
    // "Añadir lista" is the top right corner: the only other widget,
    // Ajustes, is on its left.
    Element focused() => focusedNode().context! as Element;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == focused()),
        matching: find.widgetWithText(FilledButton, 'Añadir lista'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == focused()),
        matching: find.byTooltip('Ajustes'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Inicio opened from Listas with the remote', (tester) async {
    useTvView(tester);
    _skipFirstRun(demo.db);
    await _pumpIptvApp(tester, demo.db);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsOneWidget);
    await expectFocusAndArrows(tester);
  });

  for (final section in ['Películas', 'Series']) {
    testWidgets('$section opened from the side bar', (tester) async {
      useTvView(tester);
      _skipFirstRun(demo.db);
      await _pumpIptvApp(tester, demo.db);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      await expectFocusAndArrows(tester);
    });
  }

  testWidgets('Directo', (tester) async {
    useTvView(tester);
    final player = FakePlayer();
    await pumpTvApp(
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
    await tester.pump(const Duration(milliseconds: 500));
    await expectFocusAndArrows(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('movie page', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      MovieDetailScreen(
        db: demo.db,
        playlist: demo.playlist,
        passwords: MemoryPasswordStore(),
        movie: demo.movies.first,
      ),
    );
    await tester.pumpAndSettle();
    await expectFocusAndArrows(tester);
  });

  testWidgets('series page', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      SeriesDetailScreen(
        db: demo.db,
        playlist: demo.playlist,
        passwords: MemoryPasswordStore(),
        series: demo.firstSeries,
        m3uEpisodes: demo.firstShow,
      ),
    );
    await tester.pumpAndSettle();
    await expectFocusAndArrows(tester);
  });

  // The episodes load after the first frame: the play button they bring
  // must take the focus from the back arrow focused meanwhile.
  testWidgets('series page focuses Reproducir once the episodes load', (
    tester,
  ) async {
    useTvView(tester);
    await pumpTvApp(tester, demo.db, const SizedBox.shrink());
    // Pushed, as from Series: the app bar then has a back arrow, focused
    // while the episodes load.
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => SeriesDetailScreen(
                db: demo.db,
                playlist: demo.playlist,
                passwords: MemoryPasswordStore(),
                series: demo.firstSeries,
                m3uEpisodes: demo.firstShow,
              ),
            ),
          ),
    );
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.widgetWithText(FilledButton, 'Reproducir'),
      ),
      findsOneWidget,
      reason: 'focus is on ${focused.widget}',
    );
  });

  for (final ofPlaylist in [false, true]) {
    testWidgets('Ajustes${ofPlaylist ? ' of a playlist' : ''}', (tester) async {
      useTvView(tester);
      await pumpTvApp(
        tester,
        demo.db,
        SettingsScreen(
          db: demo.db,
          passwords: MemoryPasswordStore(),
          playlist: ofPlaylist ? demo.playlist : null,
        ),
      );
      await tester.pumpAndSettle();
      await expectFocusAndArrows(tester);
    });
  }

  for (final editing in [false, true]) {
    testWidgets('playlist form${editing ? ' editing' : ''}', (tester) async {
      useTvView(tester);
      await pumpTvApp(
        tester,
        demo.db,
        PlaylistFormScreen(initial: editing ? demo.playlist : null),
      );
      await tester.pumpAndSettle();
      await expectFocusAndArrows(tester);
    });
  }

  testWidgets('channel sort sheet', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      _opener(
        (context) =>
            showSortSheet(context, current: const ChannelSort(), isOwn: true),
      ),
    );
    await _open(tester);
    await expectFocusAndArrows(tester, dialog: true);
  });

  testWidgets('category sort sheet', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      _opener(
        (context) => showCategorySortSheet(context, current: SortMode.original),
      ),
    );
    await _open(tester);
    await expectFocusAndArrows(tester, dialog: true);
  });

  testWidgets('group order screen', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      const ReorderScreen(
        title: 'Organizar grupos',
        allowHide: true,
        items: [
          ReorderItem(id: 'a', label: 'Uno'),
          ReorderItem(id: 'b', label: 'Dos'),
          ReorderItem(id: 'c', label: 'Tres'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await expectFocusAndArrows(tester);
  });

  testWidgets('PIN dialog', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      _opener((context) => askPin(context, title: 'Nuevo PIN', confirm: true)),
    );
    await _open(tester);
    await expectFocusAndArrows(tester, dialog: true);
  });

  testWidgets('exit dialog', (tester) async {
    useTvView(tester);
    await pumpTvApp(tester, demo.db, _opener(confirmExit));
    await _open(tester);
    await expectFocusAndArrows(tester, dialog: true);
  });
}
