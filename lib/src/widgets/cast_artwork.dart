import 'package:flutter/material.dart';
import 'package:playeroff_cast/playeroff_cast.dart';

/// The poster of what [session]'s receiver plays, or a TV icon when there is
/// none to show.
///
/// The API does not report a poster, so it is the one of the video this
/// session sent ([CastSession.sentMedia]); a video sent from another phone
/// has none.
class CastArtwork extends StatelessWidget {
  const CastArtwork({
    required this.session,
    required this.playback,
    this.borderRadius = 16,
    this.iconSize = 48,
    super.key,
  });

  final CastSession session;
  final Playback? playback;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final castId = playback?.castId;
    final media = castId == null ? null : session.sentMedia(castId);
    final placeholder = Center(
      child: Icon(Icons.tv, size: iconSize, color: colors.onSurfaceVariant),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: colors.surfaceContainerHighest,
        child: switch (media?.poster) {
          final poster? => Image.network(
            poster.toString(),
            // The same headers the TV fetches it with.
            headers: media!.headers.isEmpty ? null : media.headers,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, wasSync) => wasSync
                ? child
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      placeholder,
                      AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: child,
                      ),
                    ],
                  ),
            errorBuilder: (_, _, _) => placeholder,
          ),
          null => placeholder,
        },
      ),
    );
  }
}
