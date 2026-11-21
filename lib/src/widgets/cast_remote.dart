import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playeroff_cast/playeroff_cast.dart';
import 'package:playeroff_cast/src/widgets/cast_artwork.dart';
import 'package:playeroff_cast/src/widgets/cast_session_builder.dart';
import 'package:playeroff_cast/src/widgets/cast_strings.dart';
import 'package:playeroff_cast/src/widgets/send_command.dart';

/// How far the skip buttons move, matching their icons.
const _skipStep = Duration(seconds: 10);

/// Past this width the remote stops growing and centres itself, so it does
/// not stretch across a tablet or a desktop window.
const _maxWidth = 480.0;

/// A remote control for the video on [session]'s receiver: its poster and
/// title, a seek bar, play/pause and skip, volume, the audio and subtitle
/// tracks, stop and disconnect.
///
/// Draws with the theme around it and takes the height it needs, so it fits
/// a bottom sheet as well as a page. A command the TV refuses is told in a
/// snack bar when there is a `Scaffold` above.
class CastRemote extends StatelessWidget {
  const CastRemote({
    required this.session,
    this.onEnded,
    this.onDisconnected,
    super.key,
  });

  final CastSession session;

  /// Called once when the session is over, whoever ended it; the app drops
  /// the session and closes whatever holds this widget.
  final ValueChanged<CastEndReason>? onEnded;

  /// Called after the person pressed "disconnect", besides [onEnded].
  final VoidCallback? onDisconnected;

  @override
  Widget build(BuildContext context) => CastSessionBuilder(
    session: session,
    onEnded: onEnded,
    builder: (context, playback) {
      // A closed player is the same as none: there is nothing to control.
      final current = playback?.state == PlaybackState.stopped
          ? null
          : playback;

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(session: session, casting: current != null),
              const SizedBox(height: 20),
              _Stage(session: session, playback: current),
              const SizedBox(height: 16),
              if (current == null)
                const _NothingPlaying()
              else
                _Player(session: session, playback: current),
              const SizedBox(height: 16),
              _SessionActions(
                session: session,
                playback: current,
                onDisconnected: onDisconnected,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Which TV this is, and whether it is playing.
class _Header extends StatelessWidget {
  const _Header({required this.session, required this.casting});

  final CastSession session;
  final bool casting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          casting ? Icons.cast_connected : Icons.cast,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            CastStrings.of(
              context,
            ).connection(session.receiver, casting: casting),
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The poster, with what the player is busy with drawn over it: a spinner
/// while it loads or buffers, a warning when it failed. Kept on the poster,
/// and not in a line of text, so nothing below moves as buffering comes and
/// goes.
class _Stage extends StatelessWidget {
  const _Stage({required this.session, required this.playback});

  final CastSession session;
  final Playback? playback;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overlay = switch (playback?.state) {
      PlaybackState.loading ||
      PlaybackState.buffering => const CircularProgressIndicator(),
      PlaybackState.failed => Icon(
        Icons.error_outline,
        size: 48,
        color: colors.error,
      ),
      _ => null,
    };

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CastArtwork(session: session, playback: playback),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: overlay == null
                ? const SizedBox.expand()
                : DecoratedBox(
                    key: ValueKey(overlay.runtimeType),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(child: overlay),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      CastStrings.of(context).nothingPlaying,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({required this.session, required this.playback});

  final CastSession session;
  final Playback playback;

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    final theme = Theme.of(context);
    final failed = playback.state == PlaybackState.failed;
    final castId = playback.castId;
    final title = switch (playback.title?.trim()) {
      final title? when title.isNotEmpty => title,
      _ => session.sentMedia(castId)?.title ?? strings.untitled,
    };
    // Loading and buffering are the spinner on the poster; words are for
    // what stays: it ended, or it failed and why.
    final status = switch (playback.state) {
      PlaybackState.ended || PlaybackState.failed => strings.status(playback),
      _ => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (status != null) ...[
          const SizedBox(height: 4),
          Text(
            status,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        _SeekBar(session: session, playback: playback),
        const SizedBox(height: 8),
        _Transport(session: session, playback: playback),
        const SizedBox(height: 8),
        _Volume(session: session, playback: playback),
        if (playback.audioTracks.length > 1 ||
            playback.subtitles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (playback.audioTracks.length > 1)
                _TrackButton(
                  key: const ValueKey('cast-audio'),
                  icon: Icons.audiotrack_outlined,
                  title: strings.audio,
                  tracks: playback.audioTracks,
                  activeId: playback.activeAudioId,
                  onPicked: (id) => session.setAudio(id!, castId: castId),
                ),
              if (playback.subtitles.isNotEmpty)
                _TrackButton(
                  key: const ValueKey('cast-subtitles'),
                  icon: Icons.subtitles_outlined,
                  title: strings.subtitles,
                  tracks: playback.subtitles,
                  activeId: playback.activeSubtitleId,
                  offLabel: strings.off,
                  onPicked: (id) => session.setSubtitles(id, castId: castId),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Stop, when there is something to stop, and disconnect: what ends things,
/// kept apart from the controls used while watching.
class _SessionActions extends StatelessWidget {
  const _SessionActions({
    required this.session,
    required this.playback,
    this.onDisconnected,
  });

  final CastSession session;
  final Playback? playback;
  final VoidCallback? onDisconnected;

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    final playback = this.playback;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        if (playback != null)
          OutlinedButton.icon(
            onPressed: () => sendCastCommand(
              context,
              () => session.stop(castId: playback.castId),
            ),
            icon: const Icon(Icons.stop),
            label: Text(strings.stop),
          ),
        TextButton(
          onPressed: () async {
            await session.disconnect();
            onDisconnected?.call();
          },
          child: Text(strings.disconnect),
        ),
      ],
    );
  }
}

/// The seek bar. While the person drags it, and until the TV answers the
/// seek, it shows where they put it rather than where the video still is.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.session, required this.playback});

  final CastSession session;
  final Playback playback;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// Where the thumb was put, in seconds.
  double? _target;

  /// The report that was current when the seek was sent; a newer one means
  /// the TV has caught up.
  Playback? _sentWith;

  @override
  void didUpdateWidget(_SeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sentWith != null && !identical(_sentWith, widget.playback)) {
      _target = null;
      _sentWith = null;
    }
  }

  Future<void> _seek(double seconds) async {
    setState(() => _sentWith = widget.playback);
    final taken = await sendCastCommand(
      context,
      () => widget.session.seek(
        Duration(milliseconds: (seconds * 1000).round()),
        castId: widget.playback.castId,
      ),
    );
    // Refused: no report will follow, so let go of the value now.
    if (!taken && mounted) {
      setState(() {
        _target = null;
        _sentWith = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final duration = widget.playback.duration;

    if (duration == null || duration <= Duration.zero) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          CastStrings.of(context).live,
          style: labels,
          textAlign: TextAlign.center,
        ),
      );
    }

    final max = duration.inMilliseconds / 1000;
    final position = widget.session.position ?? widget.playback.position;
    final value = (_target ?? position.inMilliseconds / 1000).clamp(0.0, max);
    final shown = Duration(milliseconds: (value * 1000).round());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          value: value,
          max: max,
          onChanged: widget.playback.state.isActive
              ? (seconds) => setState(() => _target = seconds)
              : null,
          onChangeEnd: _seek,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatCastDuration(shown), style: labels),
              Text(formatCastDuration(duration), style: labels),
            ],
          ),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.session, required this.playback});

  final CastSession session;
  final Playback playback;

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    final castId = playback.castId;
    final active = playback.state.isActive;
    final playing =
        playback.state == PlaybackState.playing ||
        playback.state == PlaybackState.buffering;
    // An ended video takes `play` to start over.
    final canToggle = active || playback.state == PlaybackState.ended;
    final side = IconButton.styleFrom(fixedSize: const Size.square(56));

    VoidCallback? when(bool enabled, Future<Object?> Function() command) =>
        enabled ? () => sendCastCommand(context, command) : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 24,
      children: [
        IconButton(
          tooltip: strings.rewind,
          style: side,
          iconSize: 32,
          icon: const Icon(Icons.replay_10),
          onPressed: when(
            active,
            () => session.skip(-_skipStep, castId: castId),
          ),
        ),
        IconButton.filled(
          tooltip: playing ? strings.pause : strings.play,
          style: IconButton.styleFrom(fixedSize: const Size.square(72)),
          iconSize: 36,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: when(
            canToggle,
            () => playing
                ? session.pause(castId: castId)
                : session.play(castId: castId),
          ),
        ),
        IconButton(
          tooltip: strings.forward,
          style: side,
          iconSize: 32,
          icon: const Icon(Icons.forward_10),
          onPressed: when(
            active,
            () => session.skip(_skipStep, castId: castId),
          ),
        ),
      ],
    );
  }
}

/// Mute and the volume slider. Like the seek bar, the slider holds the value
/// the person chose until the TV reports again.
class _Volume extends StatefulWidget {
  const _Volume({required this.session, required this.playback});

  final CastSession session;
  final Playback playback;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double? _target;
  Playback? _sentWith;

  @override
  void didUpdateWidget(_Volume oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sentWith != null && !identical(_sentWith, widget.playback)) {
      _target = null;
      _sentWith = null;
    }
  }

  Future<void> _setVolume(double level) async {
    setState(() => _sentWith = widget.playback);
    final taken = await sendCastCommand(
      context,
      () => widget.session.setVolume(
        level.round(),
        castId: widget.playback.castId,
      ),
    );
    // Refused: no report will follow, so let go of the value now.
    if (!taken && mounted) {
      setState(() {
        _target = null;
        _sentWith = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    final playback = widget.playback;
    final active = playback.state.isActive;
    final level = _target ?? playback.volume.toDouble();
    final silent = playback.muted || level == 0;

    return Row(
      children: [
        IconButton(
          tooltip: playback.muted ? strings.unmute : strings.mute,
          icon: Icon(silent ? Icons.volume_off : Icons.volume_up),
          onPressed: active
              ? () => sendCastCommand(
                  context,
                  () => widget.session.setMuted(
                    !playback.muted,
                    castId: playback.castId,
                  ),
                )
              : null,
        ),
        Expanded(
          child: Slider(
            value: level.clamp(0, 100),
            max: 100,
            semanticFormatterCallback: (value) =>
                '${strings.volume} ${value.round()}',
            onChanged: active
                ? (value) => setState(() => _target = value)
                : null,
            onChangeEnd: _setVolume,
          ),
        ),
      ],
    );
  }
}

/// A button that names the active track and drops a menu to change it.
class _TrackButton extends StatelessWidget {
  const _TrackButton({
    required this.icon,
    required this.title,
    required this.tracks,
    required this.activeId,
    required this.onPicked,
    this.offLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final List<CastTrack> tracks;
  final String? activeId;

  /// The label of the "none" choice; without it a track is always on.
  final String? offLabel;

  /// Called with the chosen track's id, or null for "none".
  final Future<Object?> Function(String? id) onPicked;

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    CastTrack? active;
    for (final track in tracks) {
      if (track.id == activeId) active = track;
    }
    final current = active == null ? offLabel : strings.trackName(active);

    Widget choice(String? id, String label) => MenuItemButton(
      onPressed: id == activeId
          ? null
          : () => sendCastCommand(context, () => onPicked(id)),
      trailingIcon: id == activeId ? const Icon(Icons.check, size: 18) : null,
      child: Text(label),
    );

    return MenuAnchor(
      menuChildren: [
        if (offLabel case final off?) choice(null, off),
        for (final track in tracks) choice(track.id, strings.trackName(track)),
      ],
      // Only the active track is written, so two buttons fit side by side
      // on a phone; the icon says which kind it is. The arrow says there is
      // a list behind the button: without it the track reads as the only one.
      builder: (context, menu, _) => Tooltip(
        message: title,
        child: OutlinedButton(
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.only(left: 16, right: 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  current ?? title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}
