import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../epg/epg_refresh.dart';
import '../legal/legal_info.dart';
import '../legal/legal_screen.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../sync/account_form.dart';
import '../sync/account_scope.dart';
import '../sync/account_service.dart';
import '../sync/auth_gateway.dart' show AccountException;
import '../sync/data_export.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/content_width.dart';
import '../ui/ghostlime_logo.dart';
import '../xtream/xtream_urls.dart';
import 'app_settings.dart';
import 'email_code_dialog.dart';
import 'parental_session.dart';
import 'pin_dialog.dart';
import 'pin_scope.dart';
import 'pin_store.dart';
import 'settings_scope.dart';
import 'settings_transfer.dart';

/// App version shown in "Acerca de"; keep in sync with `pubspec.yaml`.
const appVersion = '1.0.0';

const _railLabels = {
  HomeRail.continueWatching: 'Continuar viendo',
  HomeRail.favoriteChannels: 'Canales favoritos',
  HomeRail.favoriteMovies: 'Películas favoritas',
  HomeRail.favoriteSeries: 'Series favoritas',
  HomeRail.recentChannels: 'Vistos recientemente',
};

/// Settings: account, playback, live TV, interface, guide, content (parental control),
/// data and about. [playlist] is the open playlist, when there is one: it
/// enables editing locked categories and refreshing its guide right away.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.passwords,
    this.playlist,
  });

  final CatalogDb db;
  final PasswordStore passwords;
  final Playlist? playlist;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PinStore get _pins => PinScope.read(context);

  AppSettings get _settings => SettingsScope.read(context).value;

  void _update(AppSettings next) => SettingsScope.read(context).update(next);

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Asks for the PIN, offering the emailed reset when signed in.
  Future<bool> _verifyPin() =>
      verifyPin(context, _pins, account: AccountScope.read(context));

  /// Parental changes need the PIN unless the session is already unlocked.
  Future<bool> _authorized() async {
    if (!_settings.parentalLock || ParentalSession.unlocked.value) return true;
    final ok = await _verifyPin();
    if (ok) ParentalSession.unlocked.value = true;
    return ok;
  }

  /// Turning the lock on always creates a new PIN; turning it off asks for
  /// the current one and deletes it. Without a session and without a stored
  /// PIN there is nothing to check, so the lock just turns off.
  Future<void> _toggleParentalLock(bool on) async {
    if (on) {
      final pin = await askPin(context, title: 'Crea un PIN', confirm: true);
      if (pin == null) return;
      await _pins.setPin(pin);
      ParentalSession.unlocked.value = false;
      if (mounted) _update(_settings.copyWith(parentalLock: true));
    } else {
      final signedIn =
          AccountScope.read(context)?.status == AccountStatus.signedIn;
      final nothingToVerify = !signedIn && !await _pins.hasPin();
      if (!mounted || (!nothingToVerify && !await _verifyPin())) return;
      await _pins.clear();
      ParentalSession.unlocked.value = false;
      if (mounted) _update(_settings.copyWith(parentalLock: false));
    }
  }

  Future<void> _changePin() async {
    final hasPin = await _pins.hasPin();
    if (!mounted) return;
    if (hasPin && !await _verifyPin()) return;
    if (!mounted) return;
    final pin = await askPin(context, title: 'Nuevo PIN', confirm: true);
    if (pin == null) return;
    await _pins.setPin(pin);
    if (!mounted) return;
    _snack('PIN cambiado.');
  }

  Future<void> _unlockSession() async {
    final ok = await _verifyPin();
    if (!mounted) return;
    if (ok) {
      ParentalSession.unlocked.value = true;
      _snack('Contenido bloqueado visible hasta cerrar la app.');
      setState(() {});
    }
  }

  Future<void> _editLockedCategories() async {
    final playlist = widget.playlist;
    if (playlist == null || !await _authorized() || !mounted) return;
    final id = playlist.id!;
    final all = [
      for (final kind in MediaKind.values)
        for (final c in widget.db.categories(id, kind)) (kind, c),
    ];
    final selected = {..._settings.lockedCategories};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Categorías bloqueadas'),
          content: SizedBox(
            width: 480,
            height: 480,
            child: ListView(
              children: [
                for (final (kind, category) in all)
                  CheckboxListTile(
                    dense: true,
                    title: Text(category.name),
                    subtitle: Text(switch (kind) {
                      MediaKind.live => 'Directo',
                      MediaKind.movie => 'Películas',
                      MediaKind.series => 'Series',
                    }),
                    value: selected.contains('$id/${kind.name}/${category.id}'),
                    onChanged: (value) => setDialogState(() {
                      final key = '$id/${kind.name}/${category.id}';
                      value == true ? selected.add(key) : selected.remove(key);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) _update(_settings.copyWith(lockedCategories: result));
  }

  Future<void> _setHideAdult(bool value) async {
    if (!value && !await _authorized()) return;
    if (mounted) _update(_settings.copyWith(hideAdult: value));
  }

  /// Re-downloads the open playlist's guide so a new time offset applies.
  Future<void> _refreshGuide() async {
    final playlist = widget.playlist;
    if (playlist == null) {
      _snack('La corrección se aplicará al actualizar la guía.');
      return;
    }
    final offset = Duration(minutes: _settings.epgOffsetMinutes);
    _snack('Actualizando la guía…');
    try {
      final password = playlist.type == PlaylistType.xtream
          ? await widget.passwords.read(playlist.id!)
          : null;
      final count = await refreshEpg(
        widget.db,
        playlist,
        password: password,
        offset: offset,
      );
      if (mounted) _snack('Guía actualizada: $count programas.');
    } catch (_) {
      if (mounted) _snack('No se ha podido actualizar la guía.');
    }
  }

  Future<void> _confirm(String question, VoidCallback action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
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
    if (ok == true) action();
  }

  Future<void> _export() async {
    final bytes = Uint8List.fromList(utf8.encode(exportSettings(_settings)));
    final saved = await FilePicker.saveFile(
      fileName: 'ghostlime-ajustes.json',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (saved != null && mounted) _snack('Ajustes exportados.');
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return;
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      if (!mounted) return;
      _update(importSettings(text, current: _settings));
      _snack('Ajustes importados.');
    } on FormatException {
      if (mounted) _snack('Ese fichero no es una copia de ajustes válida.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context).value;
    final hasPlaylist = widget.playlist != null;
    // Without an account no PIN can be created or changed; a lock left on can
    // still be turned off.
    final signedIn = AccountScope.of(context)?.status == AccountStatus.signedIn;
    final canUseLock = signedIn || s.parentalLock;
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Ajustes'),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: ContentWidth.paddingFor(
              constraints.maxWidth,
              const EdgeInsets.fromLTRB(48, 8, 48, 48),
            ),
            children: [
              _AccountSection(db: widget.db),
              _Section(
                icon: Icons.play_circle_outline,
                title: 'Reproducción',
                children: [
                  _SwitchRow(
                    title: 'Decodificación por hardware',
                    subtitle:
                        'Usa la gráfica; desactívala si ves fallos de imagen.',
                    value: s.hardwareDecoding,
                    onChanged: (v) => _update(s.copyWith(hardwareDecoding: v)),
                  ),
                  _SliderRow(
                    title: 'Búfer de red',
                    subtitle: 'Más segundos aguantan mejor los cortes, pero tarda más en empezar.',
                    value: s.networkCacheSecs,
                    min: 2,
                    max: 60,
                    unit: 's',
                    onChanged: (v) => _update(s.copyWith(networkCacheSecs: v)),
                  ),
                  _SwitchRow(
                    title: 'Reconectar el directo si se corta',
                    value: s.autoReconnect,
                    onChanged: (v) => _update(s.copyWith(autoReconnect: v)),
                  ),
                  _ChoiceRow<ResumePolicy>(
                    title: 'Al abrir algo empezado',
                    value: s.resumePolicy,
                    options: const {
                      ResumePolicy.ask: 'Preguntar',
                      ResumePolicy.resume: 'Reanudar',
                      ResumePolicy.restart: 'Desde el principio',
                    },
                    onChanged: (v) => _update(s.copyWith(resumePolicy: v)),
                  ),
                  _SwitchRow(
                    title: 'Siguiente episodio automático',
                    subtitle: 'Cuenta atrás de 10 s al acabar un episodio.',
                    value: s.autoNextEpisode,
                    onChanged: (v) => _update(s.copyWith(autoNextEpisode: v)),
                  ),
                ],
              ),
              _Section(
                icon: Icons.live_tv_outlined,
                title: 'Directo',
                children: [
                  _SwitchRow(
                    title: 'Sonido en la vista previa',
                    value: s.previewSound,
                    onChanged: (v) => _update(s.copyWith(previewSound: v)),
                  ),
                  _ChoiceRow<LiveFormat>(
                    title: 'Formato de las listas nuevas',
                    value: s.defaultLiveFormat,
                    options: const {
                      LiveFormat.ts: 'TS',
                      LiveFormat.m3u8: 'HLS',
                    },
                    onChanged: (v) => _update(s.copyWith(defaultLiveFormat: v)),
                  ),
                ],
              ),
              _Section(
                icon: Icons.dashboard_outlined,
                title: 'Interfaz',
                children: [
                  _ChoiceRow<StartSection>(
                    title: 'Al abrir una lista, ir a',
                    value: s.startSection,
                    options: const {
                      StartSection.home: 'Inicio',
                      StartSection.live: 'Directo',
                      StartSection.last: 'La última',
                    },
                    onChanged: (v) => _update(s.copyWith(startSection: v)),
                  ),
                  _SwitchRow(
                    title: 'Abrir la última lista al arrancar',
                    value: s.openLastPlaylist,
                    onChanged: (v) => _update(s.copyWith(openLastPlaylist: v)),
                  ),
                  _ChoiceRow<PosterSize>(
                    title: 'Tamaño de los pósteres',
                    value: s.posterSize,
                    options: const {
                      PosterSize.small: 'Pequeño',
                      PosterSize.medium: 'Medio',
                      PosterSize.large: 'Grande',
                    },
                    onChanged: (v) => _update(s.copyWith(posterSize: v)),
                  ),
                  _Row(
                    title: 'Carruseles de Inicio',
                    trailing: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final rail in HomeRail.values)
                          FilterChip(
                            label: Text(_railLabels[rail]!),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: s.hiddenHomeRails.contains(rail)
                                  ? AppColors.text
                                  : AppColors.background,
                            ),
                            selected: !s.hiddenHomeRails.contains(rail),
                            onSelected: (visible) {
                              final hidden = {...s.hiddenHomeRails};
                              visible ? hidden.remove(rail) : hidden.add(rail);
                              _update(s.copyWith(hiddenHomeRails: hidden));
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              _Section(
                icon: Icons.calendar_month_outlined,
                title: 'Guía',
                children: [
                  _ChoiceRow<int>(
                    title: 'Actualizar automáticamente cada',
                    value: s.epgRefreshHours,
                    options: const {6: '6 h', 12: '12 h', 24: '24 h'},
                    onChanged: (v) => _update(s.copyWith(epgRefreshHours: v)),
                  ),
                  _SliderRow(
                    title: 'Corrección horaria',
                    subtitle: 'Para guías con la hora desplazada. Se aplica al actualizar.',
                    value: s.epgOffsetMinutes,
                    min: -720,
                    max: 720,
                    divisions: 48,
                    unit: ' min',
                    onChanged: (v) => _update(s.copyWith(epgOffsetMinutes: v)),
                    onChangeEnd: (_) => _refreshGuide(),
                  ),
                ],
              ),
              _Section(
                icon: Icons.shield_outlined,
                title: 'Contenido',
                children: [
                  _SwitchRow(
                    title: 'Ocultar contenido adulto',
                    subtitle: 'Categorías con XXX, Adult o +18 en el nombre.',
                    value: s.hideAdult,
                    onChanged: _setHideAdult,
                  ),
                  _SwitchRow(
                    title: 'Control parental con PIN',
                    subtitle: signedIn
                        ? 'Las categorías bloqueadas desaparecen hasta poner el PIN.'
                        : s.parentalLock
                        ? 'Al desactivarlo necesitarás iniciar sesión para volver a activarlo.'
                        : 'Inicia sesión para usar el control parental.',
                    value: s.parentalLock,
                    onChanged: canUseLock ? _toggleParentalLock : null,
                  ),
                  if (s.parentalLock)
                    _Row(
                      title: 'Bloqueo',
                      subtitle:
                          '${s.lockedCategories.length} categorías bloqueadas'
                          '${ParentalSession.unlocked.value ? ' · desbloqueado en esta sesión' : ''}',
                      trailing: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (hasPlaylist)
                            OutlinedButton(
                              onPressed: _editLockedCategories,
                              child: const Text('Elegir categorías'),
                            ),
                          if (signedIn)
                            OutlinedButton(
                              onPressed: _changePin,
                              child: const Text('Cambiar PIN'),
                            ),
                          if (!ParentalSession.unlocked.value)
                            OutlinedButton(
                              onPressed: _unlockSession,
                              child: const Text('Desbloquear'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              _Section(
                icon: Icons.storage_outlined,
                title: 'Datos',
                children: [
                  _Row(
                    title: 'Historial',
                    trailing: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _confirm('¿Borrar los vistos recientemente de todas las listas?', () {
                            widget.db.clearRecents();
                            _snack('Recientes borrados.');
                          }),
                          child: const Text('Borrar recientes'),
                        ),
                        OutlinedButton(
                          onPressed: () => _confirm('¿Olvidar dónde te quedaste en todas las películas y series?', () {
                            widget.db.clearAllProgress();
                            _snack('Progreso borrado.');
                          }),
                          child: const Text('Borrar progreso'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            PaintingBinding.instance.imageCache.clear();
                            _snack('Caché de imágenes vaciada.');
                          },
                          child: const Text('Vaciar caché de imágenes'),
                        ),
                      ],
                    ),
                  ),
                  _Row(
                    title: 'Copia de seguridad de los ajustes',
                    subtitle: 'Sin contraseñas ni PIN.',
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _export,
                          child: const Text('Exportar'),
                        ),
                        OutlinedButton(
                          onPressed: _import,
                          child: const Text('Importar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _Section(
                icon: Icons.info_outline,
                title: 'Acerca de',
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      spacing: 16,
                      children: [
                        GhostlimeLogo(size: 56, semanticLabel: 'Ghostlime'),
                        Expanded(
                          child: _Row(
                            title: 'Ghostlime IPTV',
                            subtitle:
                                'Versión $appVersion · reproductor libmpv',
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Row(
                    title: 'Licencias',
                    subtitle: 'Apache-2.0 y componentes de terceros',
                    trailing: TextButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'Ghostlime IPTV',
                        applicationVersion: appVersion,
                        applicationLegalese:
                            '© 2026 guimo-dev · Apache-2.0\n'
                            'El nombre y el logo de Ghostlime no están incluidos '
                            'en la licencia.',
                      ),
                      child: const Text('Ver'),
                    ),
                  ),
                  for (final doc in LegalDoc.values)
                    _Row(
                      title: doc.title,
                      trailing: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LegalScreen(doc: doc),
                          ),
                        ),
                        child: const Text('Ver'),
                      ),
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

/// Titled card grouping related settings.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 20, endIndent: 20),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting row: title, optional explanation and a control on the right.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 24),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// `null` shows the switch disabled.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    trailing: SegmentedButton<T>(
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.04),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.text,
        ),
      ),
      segments: [
        for (final MapEntry(:key, :value) in options.entries)
          ButtonSegment(value: key, label: Text(value)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    ),
  );
}

/// Integer slider. While dragging it shows the value locally and reports it
/// once on release; keyboard steps are reported immediately.
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.subtitle,
    this.divisions,
    this.onChangeEnd,
  });

  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final int? divisions;
  final String unit;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  /// Value shown while the thumb is being dragged; `null` otherwise.
  int? _dragValue;

  @override
  Widget build(BuildContext context) {
    final shown = _dragValue ?? widget.value;
    return _Row(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 260,
            child: Slider(
              value: shown.toDouble().clamp(
                widget.min.toDouble(),
                widget.max.toDouble(),
              ),
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.divisions ?? (widget.max - widget.min),
              onChangeStart: (v) => _dragValue = v.round(),
              onChanged: (v) {
                if (_dragValue == null) return widget.onChanged(v.round());
                setState(() => _dragValue = v.round());
              },
              onChangeEnd: (v) {
                setState(() => _dragValue = null);
                widget.onChanged(v.round());
                widget.onChangeEnd?.call(v.round());
              },
            ),
          ),
          SizedBox(
            width: 72,
            child: Text('$shown${widget.unit}', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// "Cuenta" section: sign in or up (the shared [AccountForm]), sync state and
/// password management. Everything is driven by the [AccountService] in
/// [AccountScope]; without one it only explains that sync is not configured.
class _AccountSection extends StatefulWidget {
  const _AccountSection({required this.db});

  final CatalogDb db;

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  bool _busy = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Saves a JSON file with the local data of the user (see [exportUserData]).
  Future<void> _exportData() async {
    final text = exportUserDataJson(
      widget.db,
      SettingsScope.read(context).value,
    );
    try {
      final saved = await FilePicker.saveFile(
        fileName: 'ghostlime-mis-datos.json',
        bytes: Uint8List.fromList(utf8.encode(text)),
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (saved != null && mounted) _snack('Datos exportados.');
    } catch (_) {
      if (mounted) _snack('No se ha podido guardar el fichero.');
    }
  }

  /// Row that exports the local data; shown with or without an account.
  Widget get _exportRow => _Row(
    title: 'Exportar mis datos',
    subtitle:
        'Listas, favoritos, progreso y ajustes en un fichero JSON. Sin '
        'contraseñas ni PIN.',
    trailing: OutlinedButton(
      onPressed: _exportData,
      child: const Text('Exportar'),
    ),
  );

  /// Runs an account action with the buttons disabled. Failures are already in
  /// the service's `lastError`, which this section shows.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AccountException {
      // Shown through AccountService.lastError.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword(AccountService account) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => PasswordDialog(
        title: 'Cambiar contraseña',
        labels: const ['Contraseña actual', 'Contraseña nueva', 'Repetir'],
        confirmLabel: 'Cambiar',
        validate: (values) {
          if (values.any((v) => v.isEmpty)) return 'Rellena los tres campos.';
          if (values[1].length < minPasswordLength) {
            return 'Usa al menos $minPasswordLength caracteres.';
          }
          if (values[1] != values[2]) return 'Las contraseñas no coinciden.';
          return null;
        },
      ),
    );
    if (values == null) return;
    await _run(() => account.changePassword(values[0], values[1]));
    if (mounted && account.lastError == null) _snack('Contraseña cambiada.');
  }

  Future<void> _resetRemote(AccountService account) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => PasswordDialog(
        title: 'Empezar de cero en la nube',
        message:
            'Se borrarán los datos que hay en la nube y se sustituirán por '
            'los de este dispositivo. Lo que solo exista en otros '
            'dispositivos se perderá. Confirma con la contraseña de tu cuenta.',
        labels: const ['Contraseña'],
        confirmLabel: 'Sustituir',
        validate: (values) =>
            values.first.isEmpty ? 'Escribe la contraseña.' : null,
      ),
    );
    if (values == null) return;
    await _run(() => account.resetRemoteData(values.first));
  }

  /// Asks once on this device for the password of an account that signed in
  /// with Google but is encrypted with its password, and opens it.
  Future<void> _unlockWithPassword(AccountService account) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => PasswordDialog(
        title: 'Contraseña de la cuenta',
        message:
            'Tus datos están cifrados con la contraseña de esta cuenta. '
            'Escríbela una vez en este dispositivo para abrirlos.',
        labels: const ['Contraseña'],
        confirmLabel: 'Abrir',
        validate: (values) =>
            values.first.isEmpty ? 'Escribe la contraseña.' : null,
      ),
    );
    if (values == null) return;
    await _run(() => account.unlockWithPassword(values.first));
  }

  Future<void> _discardLocalData(AccountService account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(
          'Se borrarán de este dispositivo todas las listas que hay ahora, '
          'con sus contraseñas, favoritos y progreso. No se puede deshacer. '
          'Después se descargarán los datos de esta cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar y descargar'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => account.resolveLocalData(merge: false));
  }

  /// Signs out after confirming. With the parental lock on it asks for the
  /// PIN first and, when right, turns the lock off and deletes the PIN (no
  /// PIN can exist without an account); cancelling keeps the session.
  Future<void> _signOut(AccountService account) async {
    final locked = SettingsScope.read(context).value.parentalLock;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          '¿Cerrar sesión? Tus datos se quedan en este dispositivo, pero '
          'dejarán de sincronizarse.'
          '${locked ? ' El control parental se desactivará y se borrará el PIN.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (locked) {
      final pins = PinScope.read(context);
      if (!await verifyPin(context, pins, account: account)) return;
      await pins.clear();
      ParentalSession.unlocked.value = false;
      if (!mounted) return;
      final settings = SettingsScope.read(context);
      settings.update(settings.value.copyWith(parentalLock: false));
    }
    await _run(account.signOut);
  }

  /// Deletes the account: emails a code and, once it is typed (with the
  /// "Borrar también de este dispositivo" choice), deletes the account on the
  /// server and closes the session. A failed first send shows its error in a
  /// snack bar. Buttons stay disabled meanwhile, so no second code is sent.
  Future<void> _deleteAccount(AccountService account) => _run(() async {
    try {
      await account.sendDeleteAccountCode();
    } on AccountException catch (e) {
      if (mounted) _snack(e.message);
      return;
    }
    if (!mounted) return;
    var wipeDevice = false;
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => EmailCodeDialog(
        title: 'Borrar mi cuenta',
        email: account.email,
        purpose:
            'para borrar tu cuenta y todos sus datos en la nube. No se puede '
            'deshacer.',
        confirmLabel: 'Borrar cuenta',
        onSubmit: (code) =>
            account.deleteAccount(code: code, wipeDevice: wipeDevice),
        onResend: account.sendDeleteAccountCode,
        extra: _WipeDeviceCheckbox(onChanged: (value) => wipeDevice = value),
      ),
    );
    if (deleted != true) return;
    ParentalSession.unlocked.value = false;
    if (mounted) _snack('Cuenta borrada.');
  });

  /// "20/10 14:32" style time for the last sync line.
  static String _time(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.day)}/${two(time.month)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    if (account == null) {
      return _Section(
        icon: Icons.account_circle_outlined,
        title: 'Cuenta',
        children: [
          const _Row(
            title: 'Sincronización no configurada',
            subtitle:
                'Esta versión no incluye los datos del servicio de '
                'sincronización. Mira docs/distribucion.md para activarla.',
          ),
          _exportRow,
        ],
      );
    }
    final lastSync = account.lastSync;
    // The form shows the account's error itself.
    final showsForm =
        account.status == AccountStatus.signedOut ||
        account.status == AccountStatus.awaitingConfirmation;
    return _Section(
      icon: Icons.account_circle_outlined,
      title: 'Cuenta',
      children: [
        switch (account.status) {
          AccountStatus.signedOut => const _Row(
            title: 'Entra o crea una cuenta',
            subtitle: accountSyncExplanation,
          ),
          AccountStatus.awaitingConfirmation => const _Row(
            title: 'Confirma tu email',
            subtitle:
                'Te hemos enviado un correo con un código. Escribe aquí '
                'abajo tu email y tu contraseña y pulsa "Introducir código".',
          ),
          AccountStatus.signedIn => _Row(
            title: account.email ?? 'Sesión iniciada',
            subtitle: account.syncing
                ? 'Sincronizando…'
                : lastSync == null
                ? 'Aún sin sincronizar'
                : 'Última sincronización: ${_time(lastSync)}',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || account.syncing ? null : account.syncNow,
                  child: const Text('Sincronizar ahora'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _changePassword(account),
                  child: const Text('Cambiar contraseña'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _signOut(account),
                  child: const Text('Cerrar sesión'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _deleteAccount(account),
                  child: const Text('Borrar mi cuenta'),
                ),
              ],
            ),
          ),
          AccountStatus.chooseLocalData => _Row(
            title: 'Esta cuenta es distinta de la anterior',
            subtitle:
                'En este dispositivo hay listas y datos de otra cuenta. Hasta '
                'que elijas no se sincroniza nada. "Unir" los sube también a '
                'esta cuenta, junto con lo que ya tenga. "Descartar" borra de '
                'este dispositivo esas listas (con sus contraseñas, favoritos '
                'y progreso) y descarga lo de esta cuenta.',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => account.resolveLocalData(merge: true)),
                  child: const Text('Unir con esta cuenta'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _discardLocalData(account),
                  child: const Text('Descartar datos locales'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _signOut(account),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
          AccountStatus.needsPassword => _Row(
            title: account.email ?? 'Sesión iniciada con Google',
            subtitle:
                'Esta cuenta se creó con email y contraseña, y tus datos '
                'están cifrados con esa contraseña: ni siquiera el servidor '
                'puede leerlos. Escríbela una vez en este dispositivo para '
                'abrirlos; no se guarda en el servidor.',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _unlockWithPassword(account),
                  child: const Text('Escribir la contraseña'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _signOut(account),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
          AccountStatus.needsReset => _Row(
            title: 'Los datos de la nube no se pueden abrir',
            subtitle:
                'Tu contraseña se restableció y los datos cifrados con la '
                'anterior ya no se pueden leer. No se ha borrado nada. Puedes '
                'empezar de cero: la nube se sustituirá por los datos de este '
                'dispositivo.',
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _resetRemote(account),
                  child: const Text('Empezar de cero en la nube'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _signOut(account),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        },
        if (account.status == AccountStatus.signedIn)
          _SwitchRow(
            title: 'Sincronizar ajustes en este dispositivo',
            subtitle:
                'Ajustes, orden de canales y grupos, grupos ocultos y el '
                'conmutador de guía de Directo. Las listas, favoritos y '
                'progreso se sincronizan siempre.',
            value: account.syncSettings,
            onChanged: account.setSyncSettings,
          ),
        _exportRow,
        if (showsForm) AccountForm(account: account),
        if (!showsForm && account.lastError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Text(
              account.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}

/// The "Borrar también de este dispositivo" checkbox of the delete-account
/// dialog; reports every change through [onChanged].
class _WipeDeviceCheckbox extends StatefulWidget {
  const _WipeDeviceCheckbox({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  State<_WipeDeviceCheckbox> createState() => _WipeDeviceCheckboxState();
}

class _WipeDeviceCheckboxState extends State<_WipeDeviceCheckbox> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _checked,
      title: const Text('Borrar también de este dispositivo'),
      subtitle: const Text(
        'Listas, favoritos, progreso, ajustes y PIN de este dispositivo.',
      ),
      onChanged: (value) {
        setState(() => _checked = value ?? false);
        widget.onChanged(_checked);
      },
    );
  }
}
