import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../settings/settings_scope.dart';
import '../xtream/xtream_urls.dart';
import 'playlist.dart';
import 'xtream_link.dart';

/// Result of the playlist form: the edited playlist and, for Xtream, the
/// password typed (`null` when left empty while editing, meaning "unchanged").
typedef PlaylistFormResult = (Playlist, String?);

/// Checks a playlist and the password typed (as in [PlaylistFormResult])
/// before saving; returns the Spanish error to show, or `null` when fine.
typedef PlaylistSourceCheck = Future<String?> Function(
  Playlist playlist,
  String? password,
);

/// Form to add or edit a playlist. Pops a [PlaylistFormResult] or `null`.
class PlaylistFormScreen extends StatefulWidget {
  const PlaylistFormScreen({super.key, this.initial, this.checkSource});

  /// Playlist being edited; `null` to create a new one.
  final Playlist? initial;

  /// Run on save; when it returns an error the form shows it and stays open.
  final PlaylistSourceCheck? checkSource;

  @override
  State<PlaylistFormScreen> createState() => _PlaylistFormScreenState();
}

/// Widest the form grows, so fields stay readable on large windows.
const _maxFormWidth = 720.0;

class _PlaylistFormScreenState extends State<PlaylistFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late PlaylistType _type = widget.initial?.type ?? PlaylistType.xtream;
  late LiveFormat _liveFormat =
      widget.initial?.liveFormat ??
      SettingsScope.read(context).value.defaultLiveFormat;
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _server = TextEditingController(text: widget.initial?.serverUrl);
  late final _username = TextEditingController(text: widget.initial?.username);
  final _password = TextEditingController();
  late final _source = TextEditingController(text: widget.initial?.source);
  late final _userAgent = TextEditingController(
    text: widget.initial?.userAgent,
  );
  late final _epgUrl = TextEditingController(text: widget.initial?.epgUrl);

  /// Whether [PlaylistFormScreen.checkSource] is running.
  bool _checking = false;

  /// Error of the last failed source check, shown above the fields.
  String? _sourceError;

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _server,
      _username,
      _password,
      _source,
      _userAgent,
      _epgUrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills server, username and password from a pasted provider link.
  void _applyLink(String text) {
    final credentials = parseXtreamLink(text);
    if (credentials == null) return;
    setState(() {
      _server.text = credentials.serverUrl;
      _username.text = credentials.username;
      _password.text = credentials.password;
    });
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['m3u', 'm3u8'],
    );
    final path = file?.path;
    if (path != null) setState(() => _source.text = path);
  }

  /// Validates the fields, checks the source and pops the result; on a failed
  /// check shows its error and keeps the form open for corrections.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final isXtream = _type == PlaylistType.xtream;
    final playlist = Playlist(
      id: widget.initial?.id,
      name: _name.text.trim(),
      type: _type,
      serverUrl: isXtream ? normalizeServerUrl(_server.text) : null,
      username: isXtream ? text(_username) : null,
      source: isXtream ? null : text(_source),
      userAgent: text(_userAgent),
      epgUrl: text(_epgUrl),
      liveFormat: _liveFormat,
      refreshedAt: widget.initial?.refreshedAt,
    );
    final password = isXtream && _password.text.isNotEmpty
        ? _password.text
        : null;
    final check = widget.checkSource;
    if (check != null) {
      setState(() {
        _checking = true;
        _sourceError = null;
      });
      String? error;
      try {
        error = await check(playlist, password);
      } catch (_) {
        // The exception text may hold the address or password: never shown.
        error = 'No se ha podido comprobar la lista.';
      } finally {
        if (mounted) {
          setState(() {
            _checking = false;
            _sourceError = error;
          });
        }
      }
      if (error != null || !mounted) return;
    }
    Navigator.of(context).pop<PlaylistFormResult>((playlist, password));
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    final isXtream = _type == PlaylistType.xtream;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar lista' : 'Añadir lista'),
        actions: [
          FilledButton(
            onPressed: _checking ? null : _save,
            child: Text(_checking ? 'Comprobando…' : 'Guardar'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxFormWidth),
              child: Column(
                spacing: 20,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<PlaylistType>(
                    segments: const [
                      ButtonSegment(
                        value: PlaylistType.xtream,
                        label: Text('Xtream'),
                      ),
                      ButtonSegment(
                        value: PlaylistType.m3uUrl,
                        label: Text('M3U (URL)'),
                      ),
                      ButtonSegment(
                        value: PlaylistType.m3uFile,
                        label: Text('M3U (fichero)'),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  if (_sourceError case final error?) _SourceError(error),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: _required,
                  ),
                  if (isXtream) ...[
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Pegar enlace del proveedor (opcional)',
                        helperText: 'Rellena servidor, usuario y contraseña',
                      ),
                      onChanged: _applyLink,
                    ),
                    TextFormField(
                      controller: _server,
                      decoration: const InputDecoration(labelText: 'Servidor'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Usuario'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        helperText: _editing
                            ? 'Vacía para mantener la actual'
                            : null,
                      ),
                      validator: _editing ? null : _required,
                    ),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Directo en',
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<LiveFormat>(
                          segments: const [
                            ButtonSegment(
                              value: LiveFormat.ts,
                              label: Text('TS'),
                            ),
                            ButtonSegment(
                              value: LiveFormat.m3u8,
                              label: Text('HLS'),
                            ),
                          ],
                          selected: {_liveFormat},
                          onSelectionChanged: (s) =>
                              setState(() => _liveFormat = s.first),
                        ),
                      ),
                    ),
                  ] else if (_type == PlaylistType.m3uUrl)
                    TextFormField(
                      controller: _source,
                      decoration: const InputDecoration(
                        labelText: 'URL de la lista',
                      ),
                      validator: _required,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _source,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Fichero',
                            ),
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _pickFile,
                          child: const Text('Elegir…'),
                        ),
                      ],
                    ),
                  TextFormField(
                    controller: _userAgent,
                    decoration: const InputDecoration(
                      labelText: 'User-Agent (opcional)',
                    ),
                  ),
                  TextFormField(
                    controller: _epgUrl,
                    decoration: const InputDecoration(
                      labelText: 'URL de la guía (opcional)',
                      helperText: 'Si se deja vacía se usa la del proveedor',
                    ),
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

/// The source check's error, in the error colour with an icon.
class _SourceError extends StatelessWidget {
  const _SourceError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: color),
        Expanded(
          child: Text(message, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
