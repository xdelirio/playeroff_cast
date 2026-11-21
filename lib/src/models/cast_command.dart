import 'package:meta/meta.dart';

/// An order for the receiver's player (`POST /v1/sessions/commands`).
///
/// Every command may name the cast it is meant for with [castId]: if the TV
/// is already playing another video the server rejects it (`cast_mismatch`)
/// instead of, say, seeking the wrong film.
@immutable
sealed class CastCommand {
  const CastCommand({this.castId});

  /// Starts again from the beginning when the video had ended.
  const factory CastCommand.play({String? castId}) = PlayCommand;
  const factory CastCommand.pause({String? castId}) = PauseCommand;

  /// Closes the receiver's player.
  const factory CastCommand.stop({String? castId}) = StopCommand;
  const factory CastCommand.seek(Duration position, {String? castId}) =
      SeekCommand;

  /// Moves by [offset] from where the video is; negative goes back.
  const factory CastCommand.skip(Duration offset, {String? castId}) =
      SkipCommand;

  /// Sets the player's volume, 0–100. Unmutes it if it was muted. Has no
  /// effect on videos a Samsung TV plays with its native player (MKV, AVI…).
  const factory CastCommand.volume(int level, {String? castId}) = VolumeCommand;
  const factory CastCommand.mute(bool muted, {String? castId}) = MuteCommand;

  /// Turns on the subtitle [trackId], or turns subtitles off with null.
  const factory CastCommand.subtitles(String? trackId, {String? castId}) =
      SubtitlesCommand;
  const factory CastCommand.audio(String trackId, {String? castId}) =
      AudioCommand;

  final String? castId;

  /// The command's `type` on the wire.
  String get type;

  /// The fields of this command besides `type` and `castId`.
  @protected
  Map<String, Object?> get arguments => const {};

  Map<String, Object?> toJson() => {
    'type': type,
    ...arguments,
    'castId': ?castId,
  };

  @override
  String toString() => 'CastCommand(${toJson()})';
}

final class PlayCommand extends CastCommand {
  const PlayCommand({super.castId});

  @override
  String get type => 'play';
}

final class PauseCommand extends CastCommand {
  const PauseCommand({super.castId});

  @override
  String get type => 'pause';
}

final class StopCommand extends CastCommand {
  const StopCommand({super.castId});

  @override
  String get type => 'stop';
}

final class SeekCommand extends CastCommand {
  const SeekCommand(this.position, {super.castId});

  final Duration position;

  @override
  String get type => 'seek';

  @override
  Map<String, Object?> get arguments => {
    'position': position.inMilliseconds / 1000,
  };
}

final class SkipCommand extends CastCommand {
  const SkipCommand(this.offset, {super.castId});

  final Duration offset;

  @override
  String get type => 'skip';

  @override
  Map<String, Object?> get arguments => {
    'seconds': offset.inMilliseconds / 1000,
  };
}

final class VolumeCommand extends CastCommand {
  const VolumeCommand(this.level, {super.castId})
    : assert(level >= 0 && level <= 100, 'volume goes from 0 to 100');

  final int level;

  @override
  String get type => 'volume';

  @override
  Map<String, Object?> get arguments => {'level': level.clamp(0, 100)};
}

final class MuteCommand extends CastCommand {
  const MuteCommand(this.muted, {super.castId});

  final bool muted;

  @override
  String get type => 'mute';

  @override
  Map<String, Object?> get arguments => {'muted': muted};
}

final class SubtitlesCommand extends CastCommand {
  const SubtitlesCommand(this.trackId, {super.castId});

  /// Null turns subtitles off.
  final String? trackId;

  @override
  String get type => 'subtitles';

  /// `trackId` is required on the wire even when it is null.
  @override
  Map<String, Object?> get arguments => {'trackId': trackId};
}

final class AudioCommand extends CastCommand {
  const AudioCommand(this.trackId, {super.castId});

  final String trackId;

  @override
  String get type => 'audio';

  @override
  Map<String, Object?> get arguments => {'trackId': trackId};
}
