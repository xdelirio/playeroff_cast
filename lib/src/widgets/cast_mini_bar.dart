import 'package:flutter/material.dart';
import 'package:playeroff_cast/playeroff_cast.dart';
import 'package:playeroff_cast/src/widgets/cast_artwork.dart';
import 'package:playeroff_cast/src/widgets/cast_session_builder.dart';
import 'package:playeroff_cast/src/widgets/cast_strings.dart';
import 'package:playeroff_cast/src/widgets/send_command.dart';

/// A one-line summary of what [session]'s receiver is playing, with a
/// play/pause button — for the bottom of a screen while the app is used for
/// something else. Tapping it is the app's cue to open the full remote.
///
/// Draws with the theme around it.
class CastMiniBar extends StatelessWidget {
  const CastMiniBar({
    required this.session,
    this.onTap,
    this.onEnded,
    super.key,
  });

  final CastSession session;
  final VoidCallback? onTap;

  /// Called once when the session is over, so the app removes the bar.
  final ValueChanged<CastEndReason>? onEnded;

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    final theme = Theme.of(context);
    final receiver = strings.receiverName(session.receiver);

    return CastSessionBuilder(
      session: session,
      onEnded: onEnded,
      builder: (context, playback) {
        final showing =
            playback != null && playback.state != PlaybackState.stopped;
        final title = showing ? playback.title : null;
        final playing =
            playback?.state == PlaybackState.playing ||
            playback?.state == PlaybackState.buffering;
        final canToggle =
            showing &&
            (playback.state.isActive || playback.state == PlaybackState.ended);

        return Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Progress(
                  session: session,
                  playback: showing ? playback : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: CastArtwork(
                          session: session,
                          playback: showing ? playback : null,
                          borderRadius: 8,
                          iconSize: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title == null || title.isEmpty
                                  ? (showing
                                        ? receiver
                                        : strings.nothingPlaying)
                                  : title,
                              style: theme.textTheme.bodyLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              (showing ? strings.status(playback) : null) ??
                                  receiver,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: playing ? strings.pause : strings.play,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: canToggle
                            ? () => sendCastCommand(
                                context,
                                () => playing
                                    ? session.pause(castId: playback.castId)
                                    : session.play(castId: playback.castId),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A hairline of progress along the top of the bar; empty for live video.
class _Progress extends StatelessWidget {
  const _Progress({required this.session, required this.playback});

  final CastSession session;
  final Playback? playback;

  @override
  Widget build(BuildContext context) {
    final duration = playback?.duration;
    final position = session.position;
    final value =
        duration == null || position == null || duration <= Duration.zero
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    // The track is named by role: the default one is a bright colour in
    // some themes, which draws a full line across an idle bar.
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
