import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/browse/browse_screen.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/home/home_screen.dart';
import 'package:iptv_player/live/live_tv_screen.dart';
import 'package:iptv_player/playlists/memory_password_store.dart';
import 'package:iptv_player/playlists/playlist_form_screen.dart';
import 'package:iptv_player/settings/email_code_dialog.dart';
import 'package:iptv_player/settings/memory_pin_store.dart';
import 'package:iptv_player/settings/pin_dialog.dart';
import 'package:iptv_player/settings/settings_controller.dart';
import 'package:iptv_player/settings/settings_scope.dart';
import 'package:iptv_player/sync/account_form.dart';
import 'package:iptv_player/sync/account_service.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/ui/choice_selector.dart';
import 'package:iptv_player/welcome/welcome_screen.dart';
import 'package:iptv_player/xtream/xtream_urls.dart';

import '../player/fake_player.dart';
import '../sync/fake_account.dart';
import '../sync/fake_passwords.dart';
import 'tv_harness.dart';

/// A page with one button that runs [open] with its context.
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

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// The editable text of the field labelled [label].
EditableText _field(WidgetTester tester, String label) => tester.widget(
  find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(TextField)),
    matching: find.byType(EditableText),
  ),
);

/// The label of the text field with the primary focus, or `null` when the
/// focus is not on a text field.
String? _focusedLabel(WidgetTester tester) {
  for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byWidget(field),
        matching: find.byType(EditableText),
      ),
    );
    if (editable.focusNode.hasPrimaryFocus) {
      return field.decoration?.labelText ?? field.decoration?.hintText;
    }
  }
  return null;
}

/// Whether the focused widget is inside a widget that [matching] finds.
bool _focusedInside(Finder matching) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .ancestor(
        of: find.byElementPredicate((e) => e == focused),
        matching: matching,
      )
      .evaluate()
      .isNotEmpty;
}

/// Whether the focused widget is inside the button that says [text].
bool _buttonFocused(String text) => _focusedInside(
  find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ),
);

/// Presses OK on the remote.
Future<void> _ok(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

/// Presses the "Siguiente" or "Hecho" key of the system keyboard.
Future<void> _imeAction(WidgetTester tester, TextInputAction action) async {
  await tester.testTextInput.receiveAction(action);
  await tester.pumpAndSettle();
}

/// Presses and releases Back on the remote; returns whether a widget took it.
Future<bool> _pressBack(WidgetTester tester) async {
  const physical = PhysicalKeyboardKey.browserBack;
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.goBack,
    platform: 'web',
    physicalKey: physical,
  );
  final up = await tester.sendKeyUpEvent(
    LogicalKeyboardKey.goBack,
    platform: 'web',
    physicalKey: physical,
  );
  await tester.pumpAndSettle();
  return up;
}

/// The system Back, as Android sends it when no widget takes the key.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Walks the fields from [labels].first with the keyboard open: each
/// "Siguiente" moves to the next label and keeps the keyboard up.
Future<void> _walkWithNext(WidgetTester tester, List<String> labels) async {
  expect(_focusedLabel(tester), labels.first);
  for (final label in labels.skip(1)) {
    await _imeAction(tester, TextInputAction.next);
    expect(_focusedLabel(tester), label);
    expect(tester.testTextInput.isVisible, isTrue, reason: label);
  }
}

AccountService _account(TvDemo demo) => AccountService(
  db: demo.db,
  auth: FakeAuthGateway({}),
  backend: InMemorySyncBackend(),
  keys: FakeKeyStore(),
  passwords: FakePasswords(),
  pins: MemoryPinStore(),
);

void main() {
  late TvDemo demo;
  setUp(() => demo = TvDemo());
  tearDown(() => demo.db.close());

  group('playlist form', () {
    testWidgets('a field takes the focus without the keyboard; OK opens it', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();

      _field(tester, 'Nombre').focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Nombre');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(_field(tester, 'Nombre').readOnly, isTrue);

      await _ok(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(_field(tester, 'Nombre').readOnly, isFalse);
      tester.testTextInput.enterText('Demo');
      await tester.pumpAndSettle();
      expect(find.text('Demo'), findsOneWidget);
    });

    testWidgets('Xtream: Siguiente walks the fields, Hecho goes to Guardar', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      _field(tester, 'Nombre').focusNode.requestFocus();
      await tester.pumpAndSettle();
      await _ok(tester);

      await _walkWithNext(tester, [
        'Nombre',
        'Pegar enlace del proveedor (opcional)',
        'Servidor',
        'Usuario',
        'Contraseña',
      ]);
      // After the password comes the next control of the form, the live
      // format; the keyboard closes.
      await _imeAction(tester, TextInputAction.next);
      expect(_focusedLabel(tester), isNull);
      expect(_focusedInside(find.byType(ChoiceSelector<LiveFormat>)), isTrue);
      expect(tester.testTextInput.isVisible, isFalse);

      _field(tester, 'User-Agent (opcional)').focusNode.requestFocus();
      await tester.pumpAndSettle();
      await _ok(tester);
      await _walkWithNext(tester, [
        'User-Agent (opcional)',
        'URL de la guía (opcional)',
      ]);
      await _imeAction(tester, TextInputAction.done);
      expect(_buttonFocused('Guardar'), isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('M3U: Siguiente walks the fields, Hecho goes to Guardar', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('M3U (URL)'));
      await tester.pumpAndSettle();
      _field(tester, 'Nombre').focusNode.requestFocus();
      await tester.pumpAndSettle();
      await _ok(tester);

      await _walkWithNext(tester, [
        'Nombre',
        'URL de la lista',
        'User-Agent (opcional)',
        'URL de la guía (opcional)',
      ]);
      await _imeAction(tester, TextInputAction.done);
      expect(_buttonFocused('Guardar'), isTrue);
    });

    testWidgets('Down and Up leave a field, with or without typing in it', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      _field(tester, 'Servidor').focusNode.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Usuario');
      expect(tester.testTextInput.isVisible, isFalse);

      // Typed in, then the system keyboard closed (its own Back): the
      // arrows still leave, and the next field does not open the keyboard.
      await _ok(tester);
      tester.testTextInput.enterText('demo');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Servidor');
      expect(_field(tester, 'Servidor').readOnly, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('a field near the bottom scrolls up when typing starts', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      _field(tester, 'URL de la guía (opcional)').focusNode.requestFocus();
      await tester.pumpAndSettle();
      await _ok(tester);

      // The system keyboard of a TV floats over the lower part of the
      // screen without telling the app: the field goes to the top half.
      final field = tester.getRect(
        find.ancestor(
          of: find.text('URL de la guía (opcional)'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.bottom, lessThan(viewRect(tester).height / 2));
    });

    testWidgets('Back first leaves the field, then closes the form', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(
        tester,
        demo.db,
        _opener(
          (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PlaylistFormScreen()),
          ),
        ),
      );
      await _open(tester);
      _field(tester, 'Servidor').focusNode.requestFocus();
      await tester.pumpAndSettle();
      await _ok(tester);

      await _systemBack(tester);
      expect(find.byType(PlaylistFormScreen), findsOneWidget);
      expect(_focusedLabel(tester), isNull);
      focusedNode();
      expect(tester.testTextInput.isVisible, isFalse);

      await _systemBack(tester);
      expect(find.byType(PlaylistFormScreen), findsNothing);
    });

    testWidgets('Back from a field low in the form focuses a visible control', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      _field(tester, 'URL de la guía (opcional)').focusNode.requestFocus();
      await tester.pumpAndSettle();
      await _ok(tester);

      await _systemBack(tester);
      final focused = focusedNode();
      expect(_focusedLabel(tester), isNull);
      expect(
        viewRect(tester).contains(focused.rect.center),
        isTrue,
        reason: 'the focus went off screen: $focused',
      );
    });

    testWidgets('Back keeps the scroll when the new focus is in view', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      _field(tester, 'Usuario').focusNode.requestFocus();
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = scroll.pixels;

      await _systemBack(tester);
      expect(_focusedLabel(tester), isNull);
      expect(viewRect(tester).contains(focusedNode().rect.center), isTrue);
      expect(scroll.pixels, before);
    });

    testWidgets('the picked file field lets Right and Back go on', (
      tester,
    ) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('M3U (fichero)'));
      await tester.pumpAndSettle();
      _field(tester, 'Fichero').focusNode.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_buttonFocused('Elegir…'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Fichero');
      expect(tester.testTextInput.isVisible, isFalse);

      await _systemBack(tester);
      expect(find.byType(PlaylistFormScreen), findsOneWidget);
      expect(_focusedLabel(tester), isNull);
      focusedNode();
    });

    testWidgets('a tap on a field opens the keyboard', (tester) async {
      useTvView(tester);
      await pumpTvApp(tester, demo.db, const PlaylistFormScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nombre'));
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Nombre');
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('off the TV the fields open the keyboard as before', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SettingsScope(
          controller: SettingsController(demo.db),
          child: const MaterialApp(home: PlaylistFormScreen()),
        ),
      );
      await tester.pumpAndSettle();
      _field(tester, 'Nombre').focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_field(tester, 'Nombre').readOnly, isFalse);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        _field(tester, 'Nombre').textInputAction,
        isNot(TextInputAction.next),
      );
    });
  });

  group('welcome account dialog', () {
    Future<void> openDialog(WidgetTester tester, AccountService account) async {
      await pumpTvApp(
        tester,
        demo.db,
        WelcomeScreen(account: account, termsAccepted: true, onDone: () {}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar con email'));
      await tester.pumpAndSettle();
    }

    testWidgets('the email has the focus, without the keyboard', (
      tester,
    ) async {
      useTvView(tester);
      final account = _account(demo);
      addTearDown(account.dispose);
      await openDialog(tester, account);
      expect(_focusedLabel(tester), 'Email');
      expect(tester.testTextInput.isVisible, isFalse);

      await _ok(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      await _walkWithNext(tester, ['Email', 'Contraseña']);
      await _imeAction(tester, TextInputAction.done);
      expect(_buttonFocused('Entrar'), isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('Left and Right leave a field until typing starts', (
      tester,
    ) async {
      useTvView(tester);
      final account = _account(demo);
      addTearDown(account.dispose);
      await openDialog(tester, account);
      expect(_focusedLabel(tester), 'Email');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Contraseña');
      // Reached with a key: it does not open the keyboard.
      expect(_field(tester, 'Contraseña').readOnly, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Email');

      // While typing they move the caret.
      await _ok(tester);
      tester.testTextInput.enterText('ab');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Email');
      expect(_field(tester, 'Email').controller.selection.baseOffset, 1);
    });

    testWidgets('after typing and closing the keyboard, Right leaves', (
      tester,
    ) async {
      useTvView(tester);
      final account = _account(demo);
      addTearDown(account.dispose);
      await openDialog(tester, account);
      await _ok(tester);
      tester.testTextInput.enterText('ab');
      await tester.pumpAndSettle();
      // The keyboard's own Back closes it; the app is not told.
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Contraseña');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedLabel(tester), 'Email');
    });

    testWidgets('Back first leaves the field, then closes the dialog', (
      tester,
    ) async {
      useTvView(tester);
      final account = _account(demo);
      addTearDown(account.dispose);
      await openDialog(tester, account);
      expect(_focusedLabel(tester), 'Email');

      // In a field the key is left to Android, which pops a route.
      expect(await _pressBack(tester), isFalse);
      await _systemBack(tester);
      expect(find.byType(AccountForm), findsOneWidget);
      expect(_focusedLabel(tester), isNull);
      focusedNode();

      expect(await _pressBack(tester), isTrue);
      expect(find.byType(AccountForm), findsNothing);
    });
  });

  testWidgets('PIN dialog: Siguiente to the second PIN, Hecho to Aceptar', (
    tester,
  ) async {
    useTvView(tester);
    String? pin = 'none';
    await pumpTvApp(
      tester,
      demo.db,
      _opener(
        (context) async =>
            pin = await askPin(context, title: 'Nuevo PIN', confirm: true),
      ),
    );
    await _open(tester);
    expect(_focusedLabel(tester), 'PIN');
    expect(tester.testTextInput.isVisible, isFalse);

    await _ok(tester);
    tester.testTextInput.enterText('1234');
    await _walkWithNext(tester, ['PIN', 'Repite el PIN']);
    tester.testTextInput.enterText('1234');
    await _imeAction(tester, TextInputAction.done);
    expect(_buttonFocused('Aceptar'), isTrue);
    expect(pin, 'none', reason: 'Hecho does not close the dialog by itself');

    await _ok(tester);
    expect(pin, '1234');
  });

  testWidgets('code dialog: Hecho goes to the confirm button', (tester) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      _opener(
        (context) => showDialog<bool>(
          context: context,
          builder: (_) => EmailCodeDialog(
            title: 'Recuperar el PIN',
            email: null,
            purpose: 'para crear un PIN nuevo.',
            confirmLabel: 'Comprobar',
            onSubmit: (_) async {},
            onResend: () async {},
          ),
        ),
      ),
    );
    await _open(tester);
    expect(_focusedLabel(tester), 'Código del correo');
    expect(tester.testTextInput.isVisible, isFalse);
    await _ok(tester);
    await _imeAction(tester, TextInputAction.done);
    expect(_buttonFocused('Comprobar'), isTrue);
  });

  testWidgets('password dialog: Siguiente walks, Hecho goes to confirm', (
    tester,
  ) async {
    useTvView(tester);
    await pumpTvApp(
      tester,
      demo.db,
      _opener(
        (context) => showDialog<List<String>>(
          context: context,
          builder: (_) => PasswordDialog(
            title: 'Restablecer contraseña',
            labels: const ['Código del correo', 'Contraseña nueva', 'Repetir'],
            plainFields: const {0},
            confirmLabel: 'Restablecer',
            validate: (_) => null,
          ),
        ),
      ),
    );
    await _open(tester);
    expect(tester.testTextInput.isVisible, isFalse);
    await _ok(tester);
    await _walkWithNext(tester, [
      'Código del correo',
      'Contraseña nueva',
      'Repetir',
    ]);
    await _imeAction(tester, TextInputAction.done);
    expect(_buttonFocused('Restablecer'), isTrue);
  });

  group('search and filters keep the focus after Hecho', () {
    /// Focuses the field with hint [hint], types, presses Hecho and checks
    /// the keyboard closed with the field still focused.
    Future<void> typeAndFinish(WidgetTester tester, String hint) async {
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.ancestor(
            of: find.text(hint),
            matching: find.byType(TextField),
          ),
          matching: find.byType(EditableText),
        ),
      );
      editable.focusNode.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('a');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(editable.focusNode.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
    }

    testWidgets('Inicio', (tester) async {
      useTvView(tester);
      await pumpTvApp(
        tester,
        demo.db,
        Scaffold(
          body: HomeScreen(
            db: demo.db,
            playlist: demo.playlist,
            passwords: MemoryPasswordStore(),
            onOpenSection: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await typeAndFinish(tester, 'Buscar en directo, películas y series');
      await tester.pump(const Duration(seconds: 1));
    });

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
      await typeAndFinish(tester, 'Filtrar canales');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Películas', (tester) async {
      useTvView(tester);
      await pumpTvApp(
        tester,
        demo.db,
        Scaffold(
          body: BrowseScreen(
            db: demo.db,
            playlist: demo.playlist,
            passwords: MemoryPasswordStore(),
            kind: MediaKind.movie,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await typeAndFinish(tester, 'Filtrar');
    });
  });
}
