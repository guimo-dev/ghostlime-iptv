import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_db.dart';
import 'package:iptv_player/home/home_screen.dart';
import 'package:iptv_player/legal/legal_info.dart';
import 'package:iptv_player/main.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlists_screen.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/shell/app_shell.dart';
import 'package:iptv_player/tv/exit_dialog.dart';
import 'package:iptv_player/tv/remote_keys.dart';
import 'package:iptv_player/ui/tv_device.dart';

import 'tv_harness.dart';

const _exitTitle = '¿Salir de Ghostlime?';

/// Pumps the whole app on [db] with the first run done, so it opens on
/// Listas.
Future<void> _pumpIptvApp(WidgetTester tester, CatalogDb db) async {
  db.saveWelcomeDone();
  db.saveAcceptedTermsVersion(termsVersion);
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

/// Presses the system Back, as Android does when no widget takes the key.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Records the calls of `SystemNavigator.pop` (closing the app).
List<String> _recordAppExits(WidgetTester tester) {
  final exits = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') exits.add(call.method);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return exits;
}

/// Presses and releases the Back key of the remote; returns whether a widget
/// took the release (then Android does not go back).
Future<bool> _pressBack(WidgetTester tester) async {
  // Only the web key map of the test simulator knows a Back key; the
  // shortcuts look at the logical key alone.
  const physical = PhysicalKeyboardKey.browserBack;
  final down = await tester.sendKeyDownEvent(
    LogicalKeyboardKey.goBack,
    platform: 'web',
    physicalKey: physical,
  );
  final up = await tester.sendKeyUpEvent(
    LogicalKeyboardKey.goBack,
    platform: 'web',
    physicalKey: physical,
  );
  // Android goes back on an unhandled release, whatever happened to the
  // press: the release must be taken for Back to stay in the app.
  expect(down, isFalse, reason: 'the press of Back is left to Android');
  return up;
}

/// Whether section [type] is the one on screen.
bool _shows(Type type) => find.byType(type).hitTestable().evaluate().isNotEmpty;

void main() {
  late TvDemo demo;
  setUp(() => demo = TvDemo());
  tearDown(() {
    demo.db.close();
    debugTvDevice = null;
  });

  test('the remote keys map to their intents', () {
    Intent? of(LogicalKeyboardKey key) => remoteShortcuts.entries
        .singleWhere((e) => e.key.triggers!.contains(key))
        .value;

    for (final key in [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
    ]) {
      expect(of(key), isA<ActivateIntent>(), reason: '$key');
    }
    expect(of(LogicalKeyboardKey.goBack), isA<DismissIntent>());
    expect(of(LogicalKeyboardKey.escape), isA<DismissIntent>());
    expect((of(LogicalKeyboardKey.channelUp)! as ChannelStepIntent).step, 1);
    expect((of(LogicalKeyboardKey.channelDown)! as ChannelStepIntent).step, -1);
    expect(of(LogicalKeyboardKey.mediaPlayPause), isA<PlayPauseIntent>());
    expect(of(LogicalKeyboardKey.mediaPlay), isA<PlayIntent>());
    expect(of(LogicalKeyboardKey.mediaPause), isA<PauseIntent>());
    expect(
      (of(LogicalKeyboardKey.mediaFastForward)! as SeekIntent).offset,
      const Duration(seconds: 10),
    );
    expect(
      (of(LogicalKeyboardKey.mediaRewind)! as SeekIntent).offset,
      const Duration(seconds: -10),
    );
    expect(of(LogicalKeyboardKey.contextMenu), isA<QuickOptionsIntent>());
    final digits = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final numpad = [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    for (var d = 0; d < 10; d++) {
      expect((of(digits[d])! as ChannelDigitIntent).digit, d);
      expect((of(numpad[d])! as ChannelDigitIntent).digit, d);
    }
  });

  testWidgets('the app uses the remote keys only on a TV', (tester) async {
    debugTvDevice = false;
    expect(appShortcuts(), isNull);
    debugTvDevice = true;
    final shortcuts = appShortcuts()!;
    for (final MapEntry(:key, :value) in WidgetsApp.defaultShortcuts.entries) {
      if (remoteShortcuts.containsKey(key)) continue;
      expect(shortcuts[key], value);
    }
    for (final MapEntry(:key, :value) in remoteShortcuts.entries) {
      expect(shortcuts[key], value);
    }
  });

  // The live player's own handling of them is in tv_live_controls_test.
  testWidgets('remote keys reach the focused screen as intents', (
    tester,
  ) async {
    useTvView(tester);
    final steps = <int>[];
    final digits = <int>[];
    final other = <Intent>[];
    await pumpTvApp(
      tester,
      demo.db,
      const Scaffold(body: Focus(autofocus: true, child: SizedBox.expand())),
      actions: {
        ChannelStepIntent: CallbackAction<ChannelStepIntent>(
          onInvoke: (intent) => steps.add(intent.step),
        ),
        ChannelDigitIntent: CallbackAction<ChannelDigitIntent>(
          onInvoke: (intent) => digits.add(intent.digit),
        ),
        PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: other.add),
        SeekIntent: CallbackAction<SeekIntent>(onInvoke: other.add),
        QuickOptionsIntent: CallbackAction<QuickOptionsIntent>(
          onInvoke: other.add,
        ),
      },
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.channelUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.channelDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad2);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);

    expect(steps, [1, -1]);
    expect(digits, [4, 2]);
    expect(other, [
      isA<PlayPauseIntent>(),
      isA<SeekIntent>().having(
        (i) => i.offset,
        'offset',
        const Duration(seconds: 10),
      ),
      isA<QuickOptionsIntent>(),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Back on a TV: section, Inicio, Listas, exit dialog', (
    tester,
  ) async {
    useTvView(tester);
    final exits = _recordAppExits(tester);
    await _pumpIptvApp(tester, demo.db);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Películas'));
    await tester.pumpAndSettle();
    expect(_shows(HomeScreen), isFalse);

    await _back(tester);
    expect(find.byType(AppShell), findsOneWidget);
    expect(_shows(HomeScreen), isTrue);

    await _back(tester);
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(PlaylistsScreen), findsOneWidget);
    expect(find.text(_exitTitle), findsNothing);

    await _back(tester);
    expect(find.text(_exitTitle), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text(_exitTitle), findsNothing);
    expect(exits, isEmpty);

    // Back on the dialog closes it, the app stays.
    await _back(tester);
    await _back(tester);
    expect(find.text(_exitTitle), findsNothing);
    expect(exits, isEmpty);

    await _back(tester);
    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();
    expect(exits, ['SystemNavigator.pop']);
  });

  for (final size in const [Size(1440, 900), Size(390, 844)]) {
    testWidgets('no exit dialog off the TV at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final exits = _recordAppExits(tester);
      await _pumpIptvApp(tester, demo.db);
      await _back(tester);
      expect(find.text(_exitTitle), findsNothing);
      expect(exits, ['SystemNavigator.pop']);
    });
  }

  testWidgets('the Back key empties the Inicio search first', (tester) async {
    useTvView(tester);
    await _pumpIptvApp(tester, demo.db);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    // Inicio opens on the search box; OK opens the keyboard to type.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('canal');
    await tester.pumpAndSettle();

    expect(await _pressBack(tester), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('canal'), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('off the TV the Back key leaves the Inicio search alone', (
    tester,
  ) async {
    // A phone with 3-button navigation sends Back as a key too.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpIptvApp(tester, demo.db);
    await tester.tap(find.text('Lista demo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'canal');
    await tester.pumpAndSettle();

    expect(await _pressBack(tester), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('canal'), findsOneWidget);
  });

  testWidgets('the Back key closes a dialog but leaves pages to the system', (
    tester,
  ) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              autofocus: true,
              onPressed: () => confirmExit(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    expect(await _pressBack(tester), isFalse);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text(_exitTitle), findsOneWidget);
    expect(await _pressBack(tester), isTrue);
    await tester.pumpAndSettle();
    expect(find.text(_exitTitle), findsNothing);
  });

  testWidgets('the Back key leaves a page even from a text field', (
    tester,
  ) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      const Scaffold(body: TextField(autofocus: true)),
    );
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(await _pressBack(tester), isFalse);
  });

  testWidgets('exit dialog: Cancelar has the focus and returns false', (
    tester,
  ) async {
    useTvView(tester);
    bool? answer;
    await pumpTvApp(
      tester,
      demo.db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => answer = await confirmExit(context),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.widgetWithText(TextButton, 'Cancelar'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
