import 'package:meta/meta.dart';

/// How patient the client is. The defaults follow the API's own pace; they
/// are here mostly so tests do not have to wait.
@immutable
final class CastTimings {
  const CastTimings({
    this.requestTimeout = const Duration(seconds: 15),
    this.streamIdleTimeout = const Duration(seconds: 45),
    this.pollInterval = const Duration(seconds: 3),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxRetryWindow = const Duration(seconds: 60),
  });

  /// How long a request may take before it counts as a network failure.
  final Duration requestTimeout;

  /// How long the event stream may stay silent before it is taken for dead.
  /// The server pings every 20 s, so two missed pings.
  final Duration streamIdleTimeout;

  /// How often playback is asked for while the event stream is down.
  final Duration pollInterval;

  /// The wait before reopening a stream that had been working.
  final Duration reconnectDelay;

  /// The longest the client keeps polling before it tries the stream again.
  final Duration maxRetryWindow;
}
