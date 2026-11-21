import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:playeroff_cast/playeroff_cast.dart';

/// Rebuilds with what [session]'s receiver is playing, for as long as it is
/// on screen.
///
/// It is what keeps the session's event stream open: the connection lives
/// while a widget like this one is mounted and is closed with the last one.
/// While the video plays it also rebuilds every second, so a seek bar that
/// reads [CastSession.position] moves between the TV's reports.
class CastSessionBuilder extends StatefulWidget {
  const CastSessionBuilder({
    required this.session,
    required this.builder,
    this.onEnded,
    super.key,
  });

  final CastSession session;

  /// Builds with the last known playback; null while the TV has not played
  /// anything, or before the first report arrives.
  final Widget Function(BuildContext context, Playback? playback) builder;

  /// Called once when the session is over — the TV was closed, someone else
  /// connected, or this app disconnected — so the app can drop it.
  final ValueChanged<CastEndReason>? onEnded;

  @override
  State<CastSessionBuilder> createState() => _CastSessionBuilderState();
}

class _CastSessionBuilderState extends State<CastSessionBuilder> {
  StreamSubscription<CastEvent>? _events;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(CastSessionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _unfollow();
      _follow();
    }
  }

  @override
  void dispose() {
    _unfollow();
    super.dispose();
  }

  void _follow() {
    final session = widget.session;
    if (session.isOver) {
      // Told after this frame: the app will likely remove this widget.
      final reason = session.endReason!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(widget.session, session)) {
          widget.onEnded?.call(reason);
        }
      });
      return;
    }
    _events = session.events.listen(_onEvent);
    _syncTicker();
  }

  void _unfollow() {
    unawaited(_events?.cancel());
    _events = null;
    _ticker?.cancel();
    _ticker = null;
  }

  void _onEvent(CastEvent event) {
    switch (event) {
      case PlaybackChanged():
        setState(_syncTicker);
      case CastStreamEnded(:final reason) when reason.sessionOver:
        _ticker?.cancel();
        _ticker = null;
        widget.onEnded?.call(reason);
      case CastStatusChanged() || CastStreamEnded():
        break;
    }
  }

  /// Ticks only while there is something moving to draw.
  void _syncTicker() {
    final playing = widget.session.playback?.state == PlaybackState.playing;
    if (playing && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!playing) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.session.playback);
}
