import 'package:meta/meta.dart';
import 'package:playeroff_cast/src/models/cast_status.dart';
import 'package:playeroff_cast/src/models/playback.dart';

/// Something that happened on the receiver, as a session's event stream
/// tells it.
@immutable
sealed class CastEvent {
  const CastEvent();
}

/// The player's state changed. [playback] is null while the TV has not
/// played anything yet.
final class PlaybackChanged extends CastEvent {
  const PlaybackChanged(this.playback);

  final Playback? playback;

  @override
  String toString() => 'PlaybackChanged($playback)';
}

/// One of this session's casts moved on: delivered, playing, failed…
final class CastStatusChanged extends CastEvent {
  const CastStatusChanged(this.update);

  final CastUpdate update;

  @override
  String toString() => 'CastStatusChanged($update)';
}

/// The event stream is over and will not be reopened.
final class CastStreamEnded extends CastEvent {
  const CastStreamEnded(this.reason);

  final CastEndReason reason;

  @override
  String toString() => 'CastStreamEnded(${reason.name})';
}

/// Why a session's event stream ended.
enum CastEndReason {
  /// Someone else connected to the TV.
  replaced,

  /// This app disconnected, or the TV was closed.
  disconnected,

  /// The session went 2 hours without a request.
  expired,

  /// More streams were opened with this session than the server keeps, and
  /// this was the oldest. The session itself is still good.
  superseded,

  /// The server refused the token without saying why, or gave a reason this
  /// version does not know.
  unknown;

  static CastEndReason of(String? wire) =>
      values.asNameMap()[wire] ?? CastEndReason.unknown;

  /// Whether the session is gone and only a new code brings it back.
  bool get sessionOver => this != superseded;
}
