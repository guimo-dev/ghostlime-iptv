import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'catalog/catalog_db.dart';
import 'legal/legal_info.dart';
import 'player/playback_log.dart';
import 'playlists/memory_password_store.dart';
import 'playlists/password_store.dart';
import 'playlists/playlists_screen.dart';
import 'settings/memory_pin_store.dart';
import 'settings/pin_scope.dart';
import 'settings/pin_store.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_scope.dart';
import 'settings/settings_screen.dart';
import 'sync/account_scope.dart';
import 'sync/account_service.dart';
import 'sync/auth_gateway.dart';
import 'sync/key_store.dart';
import 'sync/supabase_backend.dart';
import 'ui/app_theme.dart';
import 'welcome/first_run.dart';
import 'welcome/welcome_screen.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Route of the first-run screen, shown over the playlists at start.
const _firstRunRoute = '/first-run';

/// The throwaway data directory requested through `GHOSTLIME_DATA_DIR` in [env],
/// or `null` to use the real one.
String? isolatedDataDir(Map<String, String> env) {
  final dir = env['GHOSTLIME_DATA_DIR'];
  return dir == null || dir.isEmpty ? null : dir;
}

/// Entry point: initialises libmpv, opens the catalog and, when Supabase is
/// configured, creates the account service.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final dataDir = isolatedDataDir(Platform.environment);
  final CatalogDb db;
  final PasswordStore passwords;
  final PinStore pins;
  final String logsDir;
  if (dataDir != null) {
    await Directory(dataDir).create(recursive: true);
    db = CatalogDb.open('$dataDir/catalog.db');
    passwords = MemoryPasswordStore();
    pins = MemoryPinStore();
    logsDir = '$dataDir/logs';
  } else {
    final supportDir = await getApplicationSupportDirectory();
    db = CatalogDb.open('${supportDir.path}/catalog.db');
    passwords = const PasswordStore();
    pins = const PinStore();
    logsDir = '${supportDir.path}/logs';
  }
  final settings = SettingsController(db);
  runApp(
    IptvApp(
      db: db,
      passwords: passwords,
      pins: pins,
      settings: settings,
      playbackLog: PlaybackLog(dir: Directory(logsDir)),
      // Isolated runs never touch the real sync key or an account.
      account: dataDir != null
          ? null
          : await _createAccountService(db, passwords, pins, settings),
    ),
  );
}

/// The account service, or `null` when this build has no Supabase keys (the
/// app then works without accounts).
Future<AccountService?> _createAccountService(
  CatalogDb db,
  PasswordStore passwords,
  PinStore pins,
  SettingsController settings,
) async {
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) return null;
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
  );
  return AccountService(
    db: db,
    auth: SupabaseAuthGateway(),
    backend: SupabaseSyncBackend(),
    keys: const DataKeyStore(),
    passwords: passwords,
    pins: pins,
    onSettingsChanged: settings.reload,
  );
}

/// Root widget of the app.
class IptvApp extends StatefulWidget {
  const IptvApp({
    super.key,
    required this.db,
    required this.passwords,
    required this.settings,
    this.pins = const PinStore(),
    this.playbackLog,
    this.account,
  });

  final CatalogDb db;
  final PasswordStore passwords;
  final SettingsController settings;
  final PinStore pins;

  /// Where playback events are recorded; `null` records nothing.
  final PlaybackLog? playbackLog;

  /// `null` when sync is not configured in this build.
  final AccountService? account;

  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> {
  final _playlistsKey = GlobalKey<PlaylistsScreenState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;

  /// What to show over the playlists at start. Every account that signed in
  /// here leaves its id ([CatalogDb.syncUserId], kept after signing out), so
  /// it tells an installation where an account was used.
  late final FirstRunStep _firstRun = firstRunStep(
    welcomeDone: widget.db.welcomeDone(),
    acceptedTerms: widget.db.acceptedTermsVersion(),
    hasPlaylists: widget.db.playlists().isNotEmpty,
    usedAccount: widget.db.syncUserId() != null,
  );

  @override
  void initState() {
    super.initState();
    // Start-up work once the first frame is up, unless the first-run screen
    // covers the playlists: then it waits until that screen is done.
    if (_firstRun == FirstRunStep.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPlaylists());
    }
    // Resume the previous account session and sync, also in the background.
    unawaited(widget.account?.start());
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(widget.account?.syncNow()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Start-up work of the playlists screen: refresh stale catalogs in the
  /// background and open the last playlist if the setting asks for it.
  void _startPlaylists() {
    final playlists = _playlistsKey.currentState;
    unawaited(playlists?.refreshStale());
    playlists?.openLastPlaylist();
  }

  /// Records the welcome as done and the current terms as accepted, then
  /// uncovers the playlists and runs their start-up work. An account opened
  /// in the welcome that still needs a decision (data that cannot be opened,
  /// another account's data here, or the password of an account entered with
  /// Google) goes to Ajustes, whose Cuenta section
  /// at the top shows the choice, instead of the last playlist.
  void _finishFirstRun() {
    widget.db.saveWelcomeDone();
    widget.db.saveAcceptedTermsVersion(termsVersion);
    final navigator = _navigatorKey.currentState!;
    navigator.pop();
    final status = widget.account?.status;
    if (status == AccountStatus.needsReset ||
        status == AccountStatus.chooseLocalData ||
        status == AccountStatus.needsPassword) {
      unawaited(_playlistsKey.currentState?.refreshStale());
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SettingsScreen(db: widget.db, passwords: widget.passwords),
        ),
      );
      return;
    }
    _startPlaylists();
  }

  /// The first-run screen for [settings], over the playlists; `null` for any
  /// other route.
  Route<void>? _firstRunScreen(RouteSettings settings) {
    if (settings.name != _firstRunRoute) return null;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => _firstRun == FirstRunStep.welcome
          ? WelcomeScreen(account: widget.account, onDone: _finishFirstRun)
          : AcceptTermsScreen(onAccepted: _finishFirstRun),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AccountScope(
      service: widget.account,
      child: SettingsScope(
        controller: widget.settings,
        child: PinScope(
          store: widget.pins,
          child: MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'Ghostlime IPTV',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: PlaylistsScreen(
              key: _playlistsKey,
              db: widget.db,
              passwords: widget.passwords,
            ),
            // The playlists stay underneath, so their start-up refresh and
            // the sync of an account opened in the welcome run as usual.
            initialRoute: _firstRun == FirstRunStep.none
                ? null
                : _firstRunRoute,
            onGenerateRoute: _firstRunScreen,
          ),
        ),
      ),
    );
    final log = widget.playbackLog;
    return log == null ? app : PlaybackLogScope(log: log, child: app);
  }
}
