import 'dart:async';

import 'package:flutter/material.dart';

import '../settings/settings_screen.dart';
import 'section_stack.dart';

import '../browse/browse_screen.dart';
import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_sync.dart';
import '../home/home_screen.dart';
import '../live/live_tv_screen.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/brand_state.dart';
import '../ui/focus_card.dart';
import '../ui/ghostlime_logo.dart';
import '../xtream/xtream_client.dart';

/// One destination of the side bar.
typedef _Section = ({IconData icon, String label});

const _sections = <_Section>[
  (icon: Icons.home_outlined, label: 'Inicio'),
  (icon: Icons.live_tv_outlined, label: 'Directo'),
  (icon: Icons.movie_outlined, label: 'Películas'),
  (icon: Icons.video_library_outlined, label: 'Series'),
];

/// Section last shown in this run, for the "last section" start option.
int _lastSectionIndex = 0;

/// A playlist's main frame: a slim icon side bar and the selected section.
///
/// Sections are built the first time they are shown and then kept alive, so
/// switching back keeps the selected category and scroll position; hidden ones
/// are paused (see [SectionStack]) and reload when shown. Home is rebuilt each
/// time it is shown so its rails stay current.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.db,
    required this.playlist,
    required this.passwords,
  });

  final CatalogDb db;
  final Playlist playlist;
  final PasswordStore passwords;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = switch (SettingsScope.read(context).value.startSection) {
    StartSection.home => 0,
    StartSection.live => 1,
    StartSection.last => _lastSectionIndex,
  };
  int _homeVersion = 0;

  /// Error of the last refresh when it left the playlist without a catalog;
  /// shown instead of the (empty) sections until a retry succeeds.
  late String? _syncError = _hasCatalog()
      ? null
      : widget.db.syncError(widget.playlist.id!);
  bool _retrying = false;
  StreamSubscription<int>? _refreshes;

  @override
  void initState() {
    super.initState();
    _refreshes = widget.db.refreshes
        .where((id) => id == widget.playlist.id)
        .listen((_) => _onRefreshed());
  }

  @override
  void dispose() {
    _refreshes?.cancel();
    super.dispose();
  }

  /// A refresh finished (a retry here or one from the playlists screen behind
  /// this one): show the sections once the playlist has a catalog.
  void _onRefreshed() {
    if (!mounted) return;
    setState(
      () => _syncError = _hasCatalog()
          ? null
          : widget.db.syncError(widget.playlist.id!),
    );
  }

  /// Whether the playlist has any channel, movie or series cached.
  bool _hasCatalog() => MediaKind.values.any(
    (kind) => widget.db.channelCount(widget.playlist.id!, kind) > 0,
  );

  /// Downloads the catalog again; on success the sections replace the error.
  Future<void> _retrySync() async {
    setState(() => _retrying = true);
    String? error;
    try {
      final playlist = widget.playlist;
      final password = playlist.type == PlaylistType.xtream
          ? await widget.passwords.read(playlist.id!)
          : null;
      await syncPlaylist(widget.db, playlist, password: password);
    } on XtreamException catch (e) {
      error = e.message;
    } catch (_) {
      error = syncFailedMessage;
    }
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _syncError = error;
    });
  }

  void _go(int index) {
    _lastSectionIndex = index;
    setState(() {
      _index = index;
      if (index == 0) _homeVersion++;
    });
  }

  Widget _section(int index) {
    final db = widget.db;
    final playlist = widget.playlist;
    final passwords = widget.passwords;
    return switch (index) {
      0 => HomeScreen(
        key: ValueKey(_homeVersion),
        db: db,
        playlist: playlist,
        passwords: passwords,
        onOpenSection: _go,
      ),
      1 => LiveTvScreen(db: db, playlist: playlist, passwords: passwords),
      2 => BrowseScreen(
        db: db,
        playlist: playlist,
        passwords: passwords,
        kind: MediaKind.movie,
      ),
      _ => BrowseScreen(
        db: db,
        playlist: playlist,
        passwords: passwords,
        kind: MediaKind.series,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: Row(
          children: [
            _SideBar(
              selected: _index,
              onSelected: _go,
              onExit: () => Navigator.of(context).maybePop(),
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    db: widget.db,
                    passwords: widget.passwords,
                    playlist: widget.playlist,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _syncError == null
                  ? SectionStack(
                      index: _index,
                      count: _sections.length,
                      builder: _section,
                    )
                  : _SyncErrorPanel(
                      message: _syncError!,
                      retrying: _retrying,
                      onRetry: _retrySync,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Why the playlist could not be loaded, with a retry button (a spinner while
/// retrying).
class _SyncErrorPanel extends StatelessWidget {
  const _SyncErrorPanel({
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              BrandMessage(
                title: 'No se ha podido cargar la lista',
                message: message,
                logoSize: 96,
                dimmed: true,
                child: retrying
                    ? const BrandLoader(size: 48)
                    : FilledButton.icon(
                        autofocus: true,
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Side bar: app mark, labelled section icons with a gradient marker on the
/// active one, and "Listas" at the bottom to leave the playlist.
class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.selected,
    required this.onSelected,
    required this.onExit,
    required this.onSettings,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onExit;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        border: const Border(right: BorderSide(color: AppColors.border)),
      ),
      // Scrolls when the window is too short for every button.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const GhostlimeLogo(size: 44),
                  const SizedBox(height: 28),
                  for (var i = 0; i < _sections.length; i++)
                    _SideButton(
                      icon: _sections[i].icon,
                      label: _sections[i].label,
                      active: i == selected,
                      onTap: () => onSelected(i),
                    ),
                  const Spacer(),
                  _SideButton(
                    icon: Icons.settings_outlined,
                    label: 'Ajustes',
                    active: false,
                    onTap: onSettings,
                  ),
                  _SideButton(
                    icon: Icons.swap_horiz,
                    label: 'Listas',
                    active: false,
                    onTap: onExit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon over a small label; the active one gets a tinted pill and a gradient
/// marker on its left edge.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.text : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Stack(
        children: [
          FocusCard(
            grow: false,
            radius: 14,
            color: active ? Colors.white.withValues(alpha: 0.08) : null,
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Icon(icon, color: active ? AppColors.accent : color),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (active)
            Positioned(
              left: 0,
              top: 14,
              bottom: 14,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.accent, AppColors.accentAlt],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
