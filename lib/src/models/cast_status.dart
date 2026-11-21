import 'package:meta/meta.dart';
import 'package:playeroff_cast/src/models/json.dart';

/// How far a cast got on its way to the screen.
enum CastStatus {
  /// Sent, not on the TV yet.
  pending,

  /// The TV has it and is opening the video.
  delivered,

  /// On screen. Stays so while paused.
  playing,

  /// Played to its end.
  ended,

  /// The player was closed.
  stopped,

  /// See [CastUpdate.error].
  failed,

  /// It did not reach the TV in 5 minutes, or another cast replaced it
  /// before it did.
  expired,

  /// A status this version does not know.
  unknown;

  static CastStatus of(String? wire) =>
      values.asNameMap()[wire] ?? CastStatus.unknown;

  /// Whether the cast is over and will not change again.
  bool get isFinal => switch (this) {
    ended || stopped || failed || expired => true,
    pending || delivered || playing || unknown => false,
  };
}

/// What `POST /v1/casts` answers: the cast was accepted and is on its way.
@immutable
final class CastReceipt {
  const CastReceipt({required this.castId, required this.expiresAt});

  factory CastReceipt.fromJson(Map<String, Object?> json) => CastReceipt(
    castId: json.string('castId'),
    expiresAt: json.epochOrNull('expiresAt'),
  );

  final String castId;

  /// When the cast is dropped if the TV has not picked it up.
  final DateTime? expiresAt;
}

/// The status of one cast, from `GET /v1/casts/{castId}` or a `cast` event.
@immutable
final class CastUpdate {
  const CastUpdate({required this.castId, required this.status, this.error});

  factory CastUpdate.fromJson(Map<String, Object?> json) => CastUpdate(
    castId: json.string('castId'),
    status: CastStatus.of(json.stringOrNull('status')),
    error: json.stringOrNull('error'),
  );

  final String castId;
  final CastStatus status;

  /// Only with [CastStatus.failed]: `network`, `unsupported`, `drm`,
  /// `mixed-content`, `local-network`, or another short reason.
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is CastUpdate &&
      other.castId == castId &&
      other.status == status &&
      other.error == error;

  @override
  int get hashCode => Object.hash(castId, status, error);

  @override
  String toString() =>
      'CastUpdate($castId, ${status.name}${error == null ? '' : ', $error'})';
}
