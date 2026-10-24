import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_sync.dart';
import '../epg/epg_refresh.dart';
import '../settings/settings_scope.dart';
import '../shell/app_shell.dart';
import '../sync/account_scope.dart';
import '../sync/account_service.dart';
import '../xtream/xtream_client.dart';
import '../settings/settings_screen.dart';
import '../ui/app_theme.dart';
import '../ui/brand_state.dart';
import '../ui/backdrop.dart';
import '../ui/content_width.dart';
import '../ui/focus_card.dart';
import '../ui/ghostlime_logo.dart';
import 'password_store.dart';
import 'playlist.dart';
import 'playlist_form_screen.dart';

/// Home screen: the user's playlists with open, refresh, edit and delete.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key, required this.db, required this.passwords});

  final CatalogDb db;
  final PasswordStore passwords;

  @override
  State<PlaylistsScreen> createState() => PlaylistsScreenState();
}

/// Kinds of content counted in a playlist's subtitle, with their labels.
const _countLabels = [
  (MediaKind.live, 'directo'),
  (MediaKind.movie, 'películas'),
  (MediaKind.series, 'series'),
];

/// Narrowest a playlist card gets before the grid drops a column.
const _minCardWidth = 360.0;
const _cardSpacing = 16.0;

/// State is public so `main.dart` can run the start-up work
/// ([openLastPlaylist], [refreshStale]) once nothing covers this screen.
class PlaylistsScreenState extends State<PlaylistsScreen> {
  late List<Playlist> _playlists = widget.db.playlists();
  final Set<int> _syncing = {};
  AccountService? _account;
  DateTime? _seenAccountSync;

  @override
  void initState() {
    super.initState();
    _account = AccountScope.read(context);
    _account?.addListener(_onAccountChanged);
    _account?.playlistsToRefresh.addListener(_downloadSyncedPlaylists);
  }

  @override
  void dispose() {
    _account?.removeListener(_onAccountChanged);
    _account?.playlistsToRefresh.removeListener(_downloadSyncedPlaylists);
    super.dispose();
  }

  /// Reloads the list after an account sync finished, since it may have added,
  /// changed or removed playlists.
  void _onAccountChanged() {
    final lastSync = _account!.lastSync;
    if (lastSync == _seenAccountSync) return;
    _seenAccountSync = lastSync;
    _reload();
  }

  /// Downloads the catalog of playlists that arrived from another device, one
  /// after the other (providers often allow a single connection).
  void _downloadSyncedPlaylists() {
    final arrived = _account!.playlistsToRefresh.value;
    unawaited(() async {
      for (final playlist in arrived) {
        await sync(playlist);
      }
    }());
  }

  /// Opens the playlist used last when the setting asks for it and it still
  /// exists. Called by `main.dart` at start, after the first-run screen.
  void openLastPlaylist() {
    if (!mounted) return;
    final settings = SettingsScope.read(context).value;
    final lastId = settings.lastPlaylistId;
    if (!settings.openLastPlaylist || lastId == null) return;
    final last = widget.db.playlists().where((p) => p.id == lastId);
    if (last.isNotEmpty) _open(last.first);
  }

  void _reload() => setState(() => _playlists = widget.db.playlists());

  /// Refreshes every playlist whose cache is older than [refreshInterval].
  /// Failures show a SnackBar and never block the UI.
  Future<void> refreshStale() async {
    final now = DateTime.now();
    final interval = Duration(
      hours: SettingsScope.read(context).value.epgRefreshHours,
    );
    for (final playlist in widget.db.playlists()) {
      if (needsRefresh(playlist.refreshedAt, now)) await sync(playlist);
    }
    for (final playlist in widget.db.playlists()) {
      if (!mounted) return;
      final refreshedAt = widget.db.epgRefreshedAt(playlist.id!);
      if (needsEpgRefresh(refreshedAt, now, interval)) {
        await refreshGuide(playlist, quiet: true);
      }
    }
  }

  /// Downloads a playlist's programme guide (in a background isolate).
  /// With [quiet], a playlist without a guide source is skipped silently.
  Future<void> refreshGuide(Playlist playlist, {bool quiet = false}) async {
    final id = playlist.id!;
    if (_syncing.contains(id)) return;
    setState(() => _syncing.add(id));
    try {
      final password = playlist.type == PlaylistType.xtream
          ? await widget.passwords.read(id)
          : null;
      if (quiet && epgSource(widget.db, playlist, password) == null) return;
      if (!mounted) return;
      final minutes = SettingsScope.read(context).value.epgOffsetMinutes;
      final count = await refreshEpg(
        widget.db,
        playlist,
        password: password,
        offset: Duration(minutes: minutes),
      );
      if (!quiet) _showMessage('${playlist.name}: guía con $count programas.');
    } on XtreamException catch (e) {
      _showMessage('${playlist.name}: ${e.message}');
    } catch (_) {
      _showMessage('${playlist.name}: no se ha podido actualizar la guía.');
    } finally {
      if (mounted) {
        _syncing.remove(id);
        _reload();
      }
    }
  }

  /// Syncs one playlist, showing progress on its tile and errors in a SnackBar.
  Future<void> sync(Playlist playlist) async {
    final id = playlist.id!;
    if (_syncing.contains(id)) return;
    setState(() => _syncing.add(id));
    try {
      final password = playlist.type == PlaylistType.xtream
          ? await widget.passwords.read(id)
          : null;
      await syncPlaylist(widget.db, playlist, password: password);
    } on XtreamException catch (e) {
      _showMessage('${playlist.name}: ${e.message}');
    } catch (_) {
      // e.g. the playlist was deleted mid-sync, or secure storage failed:
      // report and keep going so other playlists still refresh.
      _showMessage('${playlist.name}: no se ha podido actualizar.');
    } finally {
      if (mounted) {
        _syncing.remove(id);
        _reload();
      }
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Checks the source of a playlist about to be saved from the form, unless
  /// an edit left server, user and password as they were. An empty
  /// [password] while editing means the saved one.
  Future<String?> _checkSource(
    Playlist? initial,
    Playlist playlist,
    String? password,
  ) async {
    if (initial != null &&
        !initial.sourceChanged(playlist) &&
        password == null) {
      return null;
    }
    final id = initial?.id;
    final checked =
        password ?? (id == null ? null : await widget.passwords.read(id));
    return checkPlaylistSource(playlist, password: checked);
  }

  Future<void> _edit([Playlist? initial]) async {
    final result = await Navigator.of(context).push<PlaylistFormResult>(
      MaterialPageRoute(
        builder: (_) => PlaylistFormScreen(
          initial: initial,
          checkSource: (playlist, password) =>
              _checkSource(initial, playlist, password),
        ),
      ),
    );
    if (result == null) return;
    final (playlist, password) = result;
    final id = widget.db.savePlaylist(playlist);
    if (playlist.type != PlaylistType.xtream) {
      await widget.passwords.delete(id);
    } else if (password != null) {
      await widget.passwords.write(id, password);
    }
    // A new source makes the cached channels meaningless: drop them and
    // fetch the new catalog right away.
    final mustSync =
        initial == null || initial.sourceChanged(playlist) || password != null;
    if (initial != null && mustSync) widget.db.clearCatalog(id);
    _reload();
    final saved = playlist.copyWith(id: id);
    if (mustSync) await sync(saved);
    if (guideChangedByEdit(
      initial,
      playlist,
      passwordChanged: password != null,
    )) {
      // Quiet for new playlists: many M3U lists simply have no guide.
      await refreshGuide(saved, quiet: initial == null);
    }
  }

  Future<void> _delete(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar lista'),
        content: Text('¿Borrar "${playlist.name}" y su catálogo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.db.deletePlaylist(playlist.id!);
    await widget.passwords.delete(playlist.id!);
    _reload();
  }

  /// Opens [playlist]'s shell and reloads the cards when it is closed, since a
  /// retry from inside may have refreshed the catalog.
  Future<void> _open(Playlist playlist) async {
    final controller = SettingsScope.read(context);
    controller.update(controller.value.copyWith(lastPlaylistId: playlist.id));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppShell(
          db: widget.db,
          playlist: playlist,
          passwords: widget.passwords,
        ),
      ),
    );
    if (mounted) _reload();
  }

  /// "3 directo · 1 películas · hace 2 h" line under each playlist (kinds
  /// without items are left out), or the error of its last refresh when that
  /// failed.
  String _subtitle(Playlist playlist) {
    final id = playlist.id!;
    if (_syncing.contains(id)) return 'Actualizando…';
    if (widget.db.syncError(id) case final error?) return 'Error: $error';
    final refreshedAt = playlist.refreshedAt;
    if (refreshedAt == null) return 'Sin actualizar';
    final counts = [
      for (final (kind, label) in _countLabels)
        if (widget.db.channelCount(id, kind) case final count when count > 0)
          '$count $label',
    ];
    return [...counts, _ago(refreshedAt)].join(' · ');
  }

  static String _ago(DateTime time) {
    final minutes = DateTime.now().difference(time).inMinutes;
    if (minutes < 1) return 'ahora';
    if (minutes < 60) return 'hace $minutes min';
    if (minutes < 60 * 24) return 'hace ${minutes ~/ 60} h';
    return 'hace ${minutes ~/ (60 * 24)} d';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: ContentWidth.paddingFor(
              constraints.maxWidth,
              const EdgeInsets.fromLTRB(48, 48, 48, 96),
              maxWidth: ContentWidths.grid,
            ),
            children: [
              Row(
                children: [
                  const GhostlimeLogo(size: 56),
                  const SizedBox(width: 16),
                  Text.rich(
                    TextSpan(
                      text: 'Ghostlime ',
                      children: [
                        TextSpan(
                          text: 'IPTV',
                          style: TextStyle(color: AppColors.accent),
                        ),
                      ],
                    ),
                    style: text.displaySmall,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Ajustes',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(
                          db: widget.db,
                          passwords: widget.passwords,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir lista'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tus listas',
                style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              if (_playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: const BrandMessage(
                    title: 'Añade tu primera lista',
                    message: 'Xtream Codes o M3U, por URL o desde un fichero.',
                    logoSize: 96,
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = max(
                      1,
                      ((constraints.maxWidth + _cardSpacing) /
                              (_minCardWidth + _cardSpacing))
                          .floor(),
                    );
                    final cardWidth =
                        (constraints.maxWidth - _cardSpacing * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: _cardSpacing,
                      runSpacing: _cardSpacing,
                      children: [
                        for (final playlist in _playlists)
                          _card(playlist, cardWidth),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One playlist as a card: open on tap, actions along the bottom.
  Widget _card(Playlist playlist, double width) {
    final text = Theme.of(context).textTheme;
    final syncing = _syncing.contains(playlist.id);
    return SizedBox(
      width: width,
      child: FocusCard(
        color: Colors.white.withValues(alpha: 0.05),
        radius: 18,
        onTap: () => _open(playlist),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    playlist.type == PlaylistType.xtream
                        ? Icons.dns_outlined
                        : Icons.list_alt,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle(playlist),
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (syncing)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                      onPressed: () => sync(playlist),
                    ),
                  Tooltip(
                    message: 'Actualizar guía',
                    child: TextButton.icon(
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Guía'),
                      onPressed: syncing ? null : () => refreshGuide(playlist),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                    onPressed: syncing ? null : () => _edit(playlist),
                  ),
                  IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: syncing ? null : () => _delete(playlist),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
