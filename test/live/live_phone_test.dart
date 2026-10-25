import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/live/live_phone_view.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/player/player_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/password_store.dart';
import 'package:iptv_player/playlists/playlist.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/ui/app_theme.dart';

import '../player/fake_player.dart';

/// Live channel `<key>` of group [group], streamed from `http://h/<key>.ts`.
Channel _channel(String key, String name, {String group = 'c'}) => Channel(
  key: key,
  name: name,
  categoryId: group,
  kind: MediaKind.live,
  url: 'http://h/$key.ts',
);

const _portrait = Size(390, 844);
const _landscape = Size(844, 390);
const _tabletPortrait = Size(800, 1280);
const _tabletLandscape = Size(1280, 800);

void main() {
  late CatalogDb db;
  late Playlist playlist;
  late FakePlayer player;

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
        Category(id: 'o', name: 'Otra', kind: MediaKind.live),
      ],
      [
        _channel('a', 'Uno'),
        _channel('b', 'Dos'),
        _channel('t', 'Tres', group: 'o'),
      ],
      DateTime.now(),
    );
    player = FakePlayer();
  });
  tearDown(() => db.close());

  /// Shows Directo on a screen of [size]; it opens the first group.
  Future<void> pumpLive(
    WidgetTester tester,
    Size size, {
    PasswordStore? passwords,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SettingsScope(
        controller: SettingsController(db),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: LiveTvScreen(
              db: db,
              playlist: playlist,
              passwords: passwords ?? MemoryPasswordStore(),
              createPlayer: (_) => (player, FakeVideoController(player)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Turns the screen to [size], as a rotation does, and lets the routes
  /// move (the video controls keep animating: no `pumpAndSettle`).
  Future<void> rotate(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await settleRoutes(tester);
  }

  Future<void> tapPhoneChannel(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PhoneChannelRow),
        matching: find.text(name),
      ),
    );
    await tester.pump();
  }

  String? previewKey(WidgetTester tester) =>
      tester.widget<LivePhoneView>(find.byType(LivePhoneView)).channel?.key;

  testWidgets('portrait phone: preview on top, schedule and list below', (
    tester,
  ) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');

    expect(find.byType(NowPanel), findsNothing);
    final preview = tester.getRect(find.byType(LivePreviewBox));
    expect(preview.width, closeTo(_portrait.width, 0.5));
    expect(preview.height, closeTo(_portrait.width * 9 / 16, 0.5));
    final schedule = tester.getRect(find.byType(PhoneSchedule));
    final firstRow = tester.getRect(find.byType(PhoneChannelRow).first);
    expect(schedule.top, greaterThanOrEqualTo(preview.bottom));
    expect(firstRow.top, greaterThanOrEqualTo(schedule.bottom));
    // No guide: the channel name and "Sin guía".
    expect(
      find.descendant(
        of: find.byType(PhoneSchedule),
        matching: find.text('Uno'),
      ),
      findsOneWidget,
    );
    expect(find.text('Sin guía'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the preview stays pinned while the list scrolls', (
    tester,
  ) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');
    final before = tester.getRect(find.byType(LivePreviewBox));

    await tester.drag(
      find.byType(PhoneChannelRow).first,
      const Offset(0, -300),
    );
    await tester.pump();

    expect(tester.getRect(find.byType(LivePreviewBox)), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping a channel changes the preview with one open', (
    tester,
  ) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');
    expect(previewKey(tester), 'a');
    expect(player.opened, ['http://h/a.ts']);

    await tapPhoneChannel(tester, 'Dos');

    expect(previewKey(tester), 'b');
    expect(player.opened, ['http://h/a.ts', 'http://h/b.ts']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping the preview goes full screen without a new open', (
    tester,
  ) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');

    await tester.tap(find.byType(LivePreviewBox));
    await settleRoutes(tester);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(player.opened, ['http://h/a.ts']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('groups are picked in a bottom sheet', (tester) async {
    await pumpLive(tester, _portrait);
    expect(find.text('Tres'), findsNothing);

    await tester.tap(find.byTooltip('Elegir grupo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otra'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PhoneChannelRow),
        matching: find.text('Tres'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in const [Size(360, 640), Size(412, 915), Size(640, 360)]) {
    testWidgets('nothing overflows at $size', (tester) async {
      await pumpLive(tester, size);
      if (size.width < size.height) await tapPhoneChannel(tester, 'Uno');
      expect(find.byType(LivePhoneView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('the top bar has the guide and sort toggles', (tester) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');
    expect(find.byTooltip('Orden'), findsOneWidget);

    await tester.tap(find.byTooltip('Guía'));
    await tester.pump();

    expect(find.byType(PhoneChannelRow), findsNothing);
    expect(find.byType(LivePreviewBox), findsOneWidget);
    expect(find.byTooltip('Guía'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rotating to landscape goes full screen with the same stream, '
      'and back to portrait returns to zapping', (tester) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');

    await rotate(tester, _landscape);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(player.opened, ['http://h/a.ts']);

    await rotate(tester, _portrait);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(previewKey(tester), 'a');
    expect(player.opened, ['http://h/a.ts']);
    expect(player.current, 'http://h/a.ts');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Back from full screen returns to zapping without reopening', (
    tester,
  ) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');
    await rotate(tester, _landscape);
    final calls = List.of(player.calls);

    // The Android Back button.
    await tester.binding.handlePopRoute();
    await settleRoutes(tester);

    expect(find.byType(PlayerScreen), findsNothing);
    expect(player.calls, calls);
    expect(previewKey(tester), 'a');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a channel tapped in landscape opens full screen', (
    tester,
  ) async {
    await pumpLive(tester, _landscape);

    await tapPhoneChannel(tester, 'Uno');
    await settleRoutes(tester);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(player.opened, ['http://h/a.ts']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning upright before the full player shows closes it '
      'when it arrives', (tester) async {
    // An Xtream playlist reads its password before the player route opens.
    final xtream = playlist.copyWith(type: PlaylistType.xtream);
    db.savePlaylist(xtream);
    playlist = xtream;
    final passwords = _GatedPasswords();
    await pumpLive(tester, _portrait, passwords: passwords);
    await tapPhoneChannel(tester, 'Uno');

    tester.view.physicalSize = _landscape;
    await tester.pump();
    tester.view.physicalSize = _portrait;
    await tester.pump();
    passwords.gate.complete();
    await settleRoutes(tester);

    expect(find.byType(PlayerScreen), findsNothing);
    expect(player.opened, ['http://h/a.ts']);
    expect(player.current, 'http://h/a.ts');
    expect(previewKey(tester), 'a');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('on a desktop a wide window neither goes full screen nor '
      'skips the preview', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpLive(tester, _portrait);
      await tapPhoneChannel(tester, 'Uno');

      await rotate(tester, _landscape);
      expect(find.byType(PlayerScreen), findsNothing);

      await tapPhoneChannel(tester, 'Dos');
      await settleRoutes(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(previewKey(tester), 'b');
      expect(player.opened, ['http://h/a.ts', 'http://h/b.ts']);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('turning to landscape with the group sheet open keeps the '
      'sheet and does not go full screen', (tester) async {
    await pumpLive(tester, _portrait);
    await tapPhoneChannel(tester, 'Uno');
    await tester.tap(find.byTooltip('Elegir grupo'));
    await tester.pumpAndSettle();

    await rotate(tester, _landscape);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(PlayerScreen, skipOffstage: false), findsNothing);
    expect(player.opened, ['http://h/a.ts']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a player that arrives after turning upright never covers the '
      'group sheet', (tester) async {
    final xtream = playlist.copyWith(type: PlaylistType.xtream);
    db.savePlaylist(xtream);
    playlist = xtream;
    final passwords = _GatedPasswords();
    await pumpLive(tester, _portrait, passwords: passwords);
    await tapPhoneChannel(tester, 'Uno');

    tester.view.physicalSize = _landscape;
    await tester.pump();
    tester.view.physicalSize = _portrait;
    await tester.pump();
    await tester.tap(find.byTooltip('Elegir grupo'));
    await tester.pumpAndSettle();
    passwords.gate.complete();
    await settleRoutes(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(PlayerScreen, skipOffstage: false), findsNothing);
    expect(player.opened, ['http://h/a.ts']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (portrait, landscape) in [
    (_portrait, _landscape),
    (_tabletPortrait, _tabletLandscape),
  ]) {
    testWidgets('rotating $portrait <-> $landscape during load keeps one '
        'stream, the state and the channel', (tester) async {
      player.openGate = Completer<void>();
      await pumpLive(tester, portrait);
      await tapPhoneChannel(tester, 'Uno');
      final state = tester.state(
        find.byType(LiveTvScreen, skipOffstage: false),
      );

      for (var i = 0; i < 3; i++) {
        tester.view.physicalSize = landscape;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        tester.view.physicalSize = portrait;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
      player.openGate!.complete();
      await settleRoutes(tester);

      expect(find.byType(PlayerScreen), findsNothing);
      expect(
        tester.state(find.byType(LiveTvScreen, skipOffstage: false)),
        same(state),
      );
      expect(player.opened, ['http://h/a.ts']);
      expect(player.current, 'http://h/a.ts');
      expect(previewKey(tester), 'a');

      await rotate(tester, landscape);
      expect(player.opened, ['http://h/a.ts']);
      expect(
        tester.state(find.byType(LiveTvScreen, skipOffstage: false)),
        same(state),
      );
      expect(
        find.byType(PlayerScreen),
        landscape == _landscape ? findsOneWidget : findsNothing,
      );
      if (landscape == _tabletLandscape) {
        expect(
          tester.widget<NowPanel>(find.byType(NowPanel)).channel?.key,
          'a',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

/// Lets routes finish their transitions (the video controls keep animating,
/// so `pumpAndSettle` would never return).
Future<void> settleRoutes(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// A password store whose reads wait for [gate], like a slow secure storage.
class _GatedPasswords implements PasswordStore {
  final gate = Completer<void>();

  @override
  Future<String?> read(int playlistId) async {
    await gate.future;
    return null;
  }

  @override
  Future<void> write(int playlistId, String password) async {}

  @override
  Future<void> delete(int playlistId) async {}
}
