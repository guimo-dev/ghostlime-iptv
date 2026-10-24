import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'catalog/catalog_db.dart';
import 'player/playback_log.dart';
import 'playlists/memory_password_store.dart';
import 'playlists/password_store.dart';
import 'playlists/playlists_screen.dart';
import 'settings/memory_pin_store.dart';
import 'settings/pin_scope.dart';
import 'settings/pin_store.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_scope.dart';
import 'sync/account_scope.dart';
import 'sync/account_service.dart';
import 'sync/auth_gateway.dart';
import 'sync/key_store.dart';
import 'sync/supabase_backend.dart';
import 'ui/app_theme.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

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
          : await _createAccountService(db, passwords, settings),
    ),
  );
}

/// The account service, or `null` when this build has no Supabase keys (the
/// app then works without accounts).
Future<AccountService?> _createAccountService(
  CatalogDb db,
  PasswordStore passwords,
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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Refresh stale catalogs once the first frame is up, in the background.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _playlistsKey.currentState?.refreshStale(),
    );
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

  @override
  Widget build(BuildContext context) {
    final app = AccountScope(
      service: widget.account,
      child: SettingsScope(
        controller: widget.settings,
        child: PinScope(
          store: widget.pins,
          child: MaterialApp(
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
          ),
        ),
      ),
    );
    final log = widget.playbackLog;
    return log == null ? app : PlaybackLogScope(log: log, child: app);
  }
}
