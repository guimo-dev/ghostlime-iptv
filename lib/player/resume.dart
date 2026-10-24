import 'package:flutter/material.dart';

import '../catalog/catalog_db.dart';
import '../catalog/catalog_models.dart';
import '../playlists/password_store.dart';
import '../playlists/playlist.dart';
import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import 'live_playback.dart';
import 'play_target.dart';
import 'player_screen.dart';
import 'stream_url.dart';

/// Formats [d] as `h:mm:ss` or `m:ss`.
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${d.inMinutes}:$seconds';
}

/// Plays [target], applying the resume policy to saved progress, recording it
/// as recent (episodes count for their series) and saving progress for VOD.
/// [subtitle] is shown under the title (e.g. the programme on air).
///
/// With [next] (and the "next episode" setting on), finishing the video offers
/// to continue with it, replacing the player; [nextOf] gives the one after
/// each following target so the chain goes on.
///
/// With [shared] (Directo), the full-screen player shows that playback, which
/// is already playing [target], instead of opening the stream again.
///
/// [onChannelStep] lets the full-screen player zap a [shared] live
/// playback to the neighbouring channels.
///
/// [onRoute] gets the player route just before it is pushed; returning
/// `false` cancels it (Directo skips it when the phone turned upright).
Future<void> playWithResume(
  BuildContext context, {
  required CatalogDb db,
  required Playlist playlist,
  required PasswordStore passwords,
  required PlayTarget target,
  String? subtitle,
  PlayTarget? next,
  PlayTarget? Function(PlayTarget current)? nextOf,
  LivePlayback? shared,
  ChannelStep? onChannelStep,
  bool Function(Route<void> route)? onRoute,
}) async {
  final navigator = Navigator.of(context);
  final route = await _playerRoute(
    context,
    navigator,
    db: db,
    playlist: playlist,
    passwords: passwords,
    target: target,
    subtitle: subtitle,
    next: next,
    nextOf: nextOf,
    shared: shared,
    onChannelStep: onChannelStep,
  );
  if (route == null || !(onRoute?.call(route) ?? true)) return;
  await navigator.push(route);
}

/// Builds the player route for [target], or `null` when it cannot be played
/// (no password) or the user dismissed the resume dialog.
Future<MaterialPageRoute<void>?> _playerRoute(
  BuildContext context,
  NavigatorState navigator, {
  required CatalogDb db,
  required Playlist playlist,
  required PasswordStore passwords,
  required PlayTarget target,
  String? subtitle,
  PlayTarget? next,
  PlayTarget? Function(PlayTarget current)? nextOf,
  LivePlayback? shared,
  ChannelStep? onChannelStep,
}) async {
  final playlistId = playlist.id!;
  final password = playlist.type == PlaylistType.xtream
      ? await passwords.read(playlistId)
      : null;
  final url = playTargetUrl(playlist, target, password);
  if (!context.mounted) return null;
  if (url == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Falta la contraseña de la lista.')),
    );
    return null;
  }

  final settings = SettingsScope.read(context).value;
  final isVod = target.kind != MediaKind.live;
  Duration? start;
  final saved = isVod ? db.progress(playlistId, target.kind, target.key) : null;
  if (saved != null && saved.isUnfinished) {
    switch (settings.resumePolicy) {
      case ResumePolicy.resume:
        start = saved.position;
      case ResumePolicy.restart:
        break;
      case ResumePolicy.ask:
        final resume = await _askResume(context, target, saved);
        if (resume == null || !context.mounted) return null;
        if (resume) start = saved.position;
    }
  }

  db.addRecent(playlistId, target.kind, target.seriesKey ?? target.key);
  final following = isVod && settings.autoNextEpisode ? next : null;
  late final MaterialPageRoute<void> route;
  route = MaterialPageRoute<void>(
    builder: (_) => PlayerScreen(
      shared: shared,
      onChannelStep: onChannelStep,
      url: url,
      title: target.title,
      subtitle: subtitle,
      userAgent: playlist.userAgent,
      startPosition: start,
      isLive: !isVod,
      onProgress: isVod
          ? (position, duration) =>
                db.saveProgress(playlistId, target, position, duration)
          : null,
      nextTitle: following?.title,
      onNext: following == null
          ? null
          : () async {
              final nextRoute = await _playerRoute(
                context,
                navigator,
                db: db,
                playlist: playlist,
                passwords: passwords,
                target: following,
                next: nextOf?.call(following),
                nextOf: nextOf,
              );
              // The user may have left the finished player meanwhile.
              if (!navigator.mounted || !route.isCurrent) return;
              if (nextRoute == null) {
                navigator.pop();
              } else {
                navigator.pushReplacement(nextRoute);
              }
            },
    ),
  );
  return route;
}

/// Asks whether to resume [saved]: `true` resumes, `false` restarts, `null`
/// means the dialog was dismissed.
Future<bool?> _askResume(
  BuildContext context,
  PlayTarget target,
  Progress saved,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(target.title),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Desde el principio'),
      ),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context, true),
        child: Text('Reanudar desde ${formatDuration(saved.position)}'),
      ),
    ],
  ),
);
