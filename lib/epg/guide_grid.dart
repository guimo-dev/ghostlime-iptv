import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../browse/catalog_images.dart';
import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../ui/brand_state.dart';
import '../ui/focus_card.dart';
import 'programme.dart';

/// Width of the visible time window and how far the arrows move it.
const _window = Duration(hours: 3);
const _step = Duration(hours: 1);
const _channelColumnWidth = 220.0;
const _rowHeight = 56.0;

/// Below this width (a phone) the grid shows a shorter window, a narrower
/// channel column and wraps its toolbar, so programmes stay readable.
const _compactWidth = 600.0;
const _compactWindow = Duration(minutes: 90);
const _compactChannelColumnWidth = 120.0;

/// Formats [time] as local `HH:mm`.
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Programme guide grid: [channels] as rows over a 3-hour window that moves
/// with the arrow buttons, with a "Solo con guía" filter. Tapping a channel
/// or any of its programmes calls [onChannel]. The parent rebuilds it (at
/// least every minute) to move the "now" marker, and bumps [revision] when
/// the guide may have changed.
class GuideGrid extends StatefulWidget {
  const GuideGrid({
    super.key,
    required this.db,
    required this.playlistId,
    required this.channels,
    required this.names,
    required this.selectedKey,
    required this.onChannel,
    this.revision = 0,
    this.clock = DateTime.now,
  });

  final CatalogDb db;
  final int playlistId;
  final List<Channel> channels;

  /// Names to show by channel key; channels missing here show their own.
  final Map<String, String> names;

  /// Key of the highlighted channel, if any.
  final String? selectedKey;
  final ValueChanged<Channel> onChannel;

  /// Changes whenever the stored guide may have changed (a refresh, the
  /// clock); the programmes are then read again.
  final int revision;

  /// The current time, for the window and the "now" marker (fixed in tests).
  final DateTime Function() clock;

  @override
  State<GuideGrid> createState() => _GuideGridState();
}

class _GuideGridState extends State<GuideGrid> {
  /// Hide channels without programmes in the window.
  bool _onlyWithGuide = false;
  Map<String, List<Programme>> _byChannel = const {};
  late DateTime _windowStart = _initialStart();

  @override
  void initState() {
    super.initState();
    _loadProgrammes();
  }

  @override
  void didUpdateWidget(GuideGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        !setEquals(_epgIds(oldWidget.channels), _epgIds(widget.channels))) {
      _loadProgrammes();
    }
  }

  /// Guide ids of [channels].
  static Set<String> _epgIds(List<Channel> channels) => {
    for (final c in channels)
      if (c.epgId != null) c.epgId!,
  };

  /// Half an hour before now, rounded down to the half hour.
  DateTime _initialStart() {
    final now = widget.clock().toLocal();
    final rounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 0 : 30,
    );
    return rounded.subtract(const Duration(minutes: 30));
  }

  void _loadProgrammes() {
    final byChannel = <String, List<Programme>>{};
    for (final p in widget.db.programmes(
      widget.playlistId,
      _epgIds(widget.channels),
      _windowStart.toUtc(),
      _windowStart.add(_window).toUtc(),
    )) {
      byChannel.putIfAbsent(p.channelId, () => []).add(p);
    }
    _byChannel = byChannel;
  }

  /// Programmes of [channel] that overlap the [window] from the start.
  List<Programme> _programmesOf(Channel channel, Duration window) {
    final start = _windowStart.toUtc();
    final end = start.add(window);
    return [
      for (final p in _byChannel[channel.epgId] ?? const <Programme>[])
        if (p.stop.isAfter(start) && p.start.isBefore(end)) p,
    ];
  }

  /// Channels listed in the grid, honoring "Solo con guía" over [window].
  List<Channel> _shownChannels(Duration window) => _onlyWithGuide
      ? widget.channels
            .where((c) => _programmesOf(c, window).isNotEmpty)
            .toList()
      : widget.channels;

  /// Moves the window to [start] and loads its programmes.
  void _moveTo(DateTime start) {
    setState(() {
      _windowStart = start;
      _loadProgrammes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildGrid(compact: constraints.maxWidth < _compactWidth),
    );
  }

  /// The toolbar, time header and rows; [compact] on narrow screens.
  Widget _buildGrid({required bool compact}) {
    final window = compact ? _compactWindow : _window;
    final columnWidth = compact
        ? _compactChannelColumnWidth
        : _channelColumnWidth;
    final end = _windowStart.add(window);
    final shown = _shownChannels(window);
    final filter = Tooltip(
      message: 'Ocultar canales sin programación',
      child: FilterChip(
        label: const Text('Solo con guía'),
        selected: _onlyWithGuide,
        onSelected: (value) => setState(() => _onlyWithGuide = value),
      ),
    );
    final timeControls = [
      IconButton(
        tooltip: 'Antes',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => _moveTo(_windowStart.subtract(_step)),
      ),
      TextButton(
        onPressed: () => _moveTo(_initialStart()),
        child: Text('${formatClock(_windowStart)}–${formatClock(end)}'),
      ),
      IconButton(
        tooltip: 'Después',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => _moveTo(_windowStart.add(_step)),
      ),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: compact
              ? Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    filter,
                    Row(mainAxisSize: MainAxisSize.min, children: timeControls),
                  ],
                )
              : Row(children: [filter, const Spacer(), ...timeControls]),
        ),
        _TimeHeader(
          start: _windowStart,
          window: window,
          channelColumnWidth: columnWidth,
        ),
        const Divider(height: 1),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: BrandMessage(
                    title: 'No hay programación en estas horas.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: shown.length,
                  itemExtent: _rowHeight,
                  itemBuilder: (context, index) {
                    final channel = shown[index];
                    return _GuideRow(
                      channel: channel,
                      name: widget.names[channel.key] ?? channel.name,
                      programmes: _programmesOf(channel, window),
                      windowStart: _windowStart,
                      window: window,
                      channelColumnWidth: columnWidth,
                      now: widget.clock().toUtc(),
                      selected: channel.key == widget.selectedKey,
                      onTap: () => widget.onChannel(channel),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Half-hour labels over the time window.
class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.start,
    required this.window,
    required this.channelColumnWidth,
  });

  final DateTime start;
  final Duration window;
  final double channelColumnWidth;

  @override
  Widget build(BuildContext context) {
    final slots = window.inMinutes ~/ 30;
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(width: channelColumnWidth),
          for (var i = 0; i < slots; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  formatClock(start.add(Duration(minutes: 30 * i))),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One channel: name on the left, its programmes laid out over the window.
/// Tapping either calls [onTap].
class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.channel,
    required this.name,
    required this.programmes,
    required this.windowStart,
    required this.window,
    required this.channelColumnWidth,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final Channel channel;
  final String name;
  final List<Programme> programmes;
  final DateTime windowStart;
  final Duration window;
  final double channelColumnWidth;

  /// The current time (UTC), where the "now" marker goes.
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final start = windowStart.toUtc();
    final end = start.add(window);
    return Row(
      children: [
        SizedBox(
          width: channelColumnWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
            child: FocusCard(
              grow: false,
              selected: selected,
              onTap: onTap,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  ChannelLogo(url: channel.iconUrl),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final perMinute = constraints.maxWidth / window.inMinutes;
              double x(DateTime t) {
                final clamped = t.isBefore(start)
                    ? start
                    : t.isAfter(end)
                    ? end
                    : t;
                return clamped.difference(start).inMinutes * perMinute;
              }

              return Stack(
                children: [
                  if (programmes.isEmpty) const Center(child: Text('Sin guía')),
                  for (final p in programmes)
                    Positioned(
                      left: x(p.start),
                      width: (x(p.stop) - x(p.start)).clamp(0, double.infinity),
                      top: 4,
                      bottom: 4,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Material(
                          color: !p.start.isAfter(now) && p.stop.isAfter(now)
                              ? colors.primaryContainer
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: onTap,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text(
                                p.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (now.isAfter(start) && now.isBefore(end))
                    Positioned(
                      left: x(now),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: colors.error),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
