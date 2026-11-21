import 'package:meta/meta.dart';
import 'package:playeroff_cast/src/models/json.dart';

/// What the receiver is playing, as it last reported it.
///
/// It belongs to the TV, not to the phone that sent the video: a phone that
/// connects later sees what is already on.
@immutable
final class Playback {
  const Playback({
    required this.castId,
    required this.state,
    required this.position,
    required this.duration,
    required this.volume,
    required this.muted,
    required this.subtitles,
    required this.activeSubtitleId,
    required this.audioTracks,
    required this.activeAudioId,
    required this.receivedAt,
    this.title,
    this.error,
    this.lastCommandId,
    this.updatedAt,
  });

  /// Reads a `Playback` of the API. [receivedAt] is this device's time when
  /// it arrived, which [positionAt] counts from.
  factory Playback.fromJson(
    Map<String, Object?> json, {
    required DateTime receivedAt,
  }) => Playback(
    castId: json.string('castId'),
    title: json.stringOrNull('title'),
    state: PlaybackState.of(json.stringOrNull('state')),
    position: json.secondsOrNull('position') ?? Duration.zero,
    duration: json.secondsOrNull('duration'),
    volume: json.numOrNull('volume')?.round() ?? 100,
    muted: json['muted'] == true,
    subtitles: json.objects('subtitles').map(CastTrack.fromJson).toList(),
    activeSubtitleId: json.stringOrNull('activeSubtitleId'),
    audioTracks: json.objects('audioTracks').map(CastTrack.fromJson).toList(),
    activeAudioId: json.stringOrNull('activeAudioId'),
    error: json.stringOrNull('error'),
    lastCommandId: json.stringOrNull('lastCommandId'),
    updatedAt: json.epochOrNull('updatedAt'),
    receivedAt: receivedAt,
  );

  /// The cast being played; commands can name it so they never land on a
  /// video that replaced it.
  final String castId;

  final String? title;
  final PlaybackState state;

  /// Where the video was when the receiver reported. While it plays the
  /// receiver only reports every 5 s: use [positionAt] to draw a seek bar.
  final Duration position;

  /// Null when unknown or live.
  final Duration? duration;

  /// The player's volume, 0–100 % of the TV's own.
  final int volume;
  final bool muted;

  final List<CastTrack> subtitles;

  /// Null when subtitles are off.
  final String? activeSubtitleId;

  final List<CastTrack> audioTracks;
  final String? activeAudioId;

  /// Only with [PlaybackState.failed]: `network`, `unsupported`, `drm`,
  /// `mixed-content`, `local-network`, or another short reason.
  final String? error;

  /// The last command the receiver applied; matches the id a command
  /// returned once it took effect.
  final String? lastCommandId;

  /// The receiver's last report, by the server's clock.
  final DateTime? updatedAt;

  /// When this state reached this device, by its own clock.
  final DateTime receivedAt;

  bool get isLive => duration == null;

  CastTrack? get activeSubtitle => _track(subtitles, activeSubtitleId);
  CastTrack? get activeAudio => _track(audioTracks, activeAudioId);

  /// The position at [now]: [position] moved forward by the time elapsed
  /// while playing, never past [duration].
  ///
  /// Counted from [receivedAt] rather than [updatedAt], so a phone and a
  /// server with different clocks do not skew it.
  Duration positionAt(DateTime now) {
    if (state != PlaybackState.playing) return position;
    final elapsed = now.difference(receivedAt);
    if (elapsed.isNegative) return position;
    final estimate = position + elapsed;
    final end = duration;
    return end != null && estimate > end ? end : estimate;
  }

  static CastTrack? _track(List<CastTrack> tracks, String? id) {
    if (id == null) return null;
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  @override
  String toString() =>
      'Playback($castId, ${state.name}, ${position.inSeconds}s'
      '${duration == null ? '' : '/${duration!.inSeconds}s'})';
}

/// The player's state on the receiver.
enum PlaybackState {
  /// The cast arrived and the video is being opened.
  loading,
  playing,
  paused,
  buffering,

  /// The video reached its end; `play` starts it again.
  ended,

  /// The player was closed, from the TV or with the `stop` command. Also
  /// what a video that went 30 s without reporting is shown as.
  stopped,

  /// See [Playback.error].
  failed,

  /// A state this version does not know.
  unknown;

  static PlaybackState of(String? wire) =>
      values.asNameMap()[wire] ?? PlaybackState.unknown;

  /// Whether a video is loaded and takes commands.
  bool get isActive => switch (this) {
    loading || playing || paused || buffering => true,
    ended || stopped || failed || unknown => false,
  };
}

/// A subtitle or audio track of the video on the receiver.
@immutable
final class CastTrack {
  const CastTrack({required this.id, required this.lang, required this.label});

  factory CastTrack.fromJson(Map<String, Object?> json) => CastTrack(
    id: json.string('id'),
    lang: json.stringOrNull('lang') ?? '',
    label: json.stringOrNull('label') ?? '',
  );

  /// Opaque: it is the receiver's own and goes back unchanged in commands.
  final String id;
  final String lang;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is CastTrack &&
      other.id == id &&
      other.lang == lang &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, lang, label);

  @override
  String toString() => 'CastTrack($id, $lang, $label)';
}
