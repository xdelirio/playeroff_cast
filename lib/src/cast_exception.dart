/// Why a call to PlayerOFF failed.
sealed class CastException implements Exception {
  const CastException(this.message);

  /// A description for logs. The API writes it in Spanish and it is not
  /// meant for the screen: pick the app's own text from the exception type
  /// and [CastApiException.code].
  final String message;
}

/// The server answered with an error.
final class CastApiException extends CastException {
  const CastApiException({
    required this.code,
    required this.statusCode,
    required String message,
    this.rawCode,
  }) : super(message);

  final CastErrorCode code;
  final int statusCode;

  /// The code as the server sent it, kept for the ones this version does
  /// not know ([CastErrorCode.unknown]).
  final String? rawCode;

  /// Whether the session is gone and only a new code brings it back: the TV
  /// was closed, someone else connected or the token expired.
  bool get sessionOver =>
      code == CastErrorCode.unauthorized || code == CastErrorCode.sessionEnded;

  /// Whether the same call can succeed later without changing anything.
  bool get retryable =>
      code == CastErrorCode.rateLimited || code == CastErrorCode.internal;

  @override
  String toString() =>
      'CastApiException($statusCode ${rawCode ?? code.name}): $message';
}

/// The server could not be reached, or did not answer in time.
final class CastNetworkException extends CastException {
  const CastNetworkException(super.message, {this.cause});

  final Object? cause;

  @override
  String toString() => 'CastNetworkException: $message';
}

/// The error codes of the API (`error.code`).
enum CastErrorCode {
  /// 400 — the body is wrong; the message names the field.
  validationError('validation_error'),

  /// 401 — the token is invalid or expired. Same meaning as [sessionEnded]
  /// for an app.
  unauthorized('unauthorized'),

  /// 404 — the code does not exist, was already used or expired.
  invalidCode('invalid_code'),

  /// 404 — the cast does not exist or belongs to another session.
  notFound('not_found'),

  /// 410 — the TV was closed or someone else connected to it.
  sessionEnded('session_ended'),

  /// 409 — a command was sent with no video loaded.
  nothingPlaying('nothing_playing'),

  /// 409 — the command named a cast that is no longer the one playing.
  castMismatch('cast_mismatch'),

  /// 413 — the body is over 32 KB.
  payloadTooLarge('payload_too_large'),

  /// 429 — too many requests; wait a few seconds.
  rateLimited('rate_limited'),

  /// 500 — the server failed.
  internal('internal'),

  /// A code this version does not know, or a response that was not an API
  /// error at all (a proxy's HTML page).
  unknown('');

  const CastErrorCode(this.wire);

  final String wire;

  /// The code for what the server sent, falling back on the status when the
  /// body carried no known code.
  static CastErrorCode of(String? wire, int statusCode) {
    for (final code in values) {
      if (code.wire == wire && code != unknown) return code;
    }
    return switch (statusCode) {
      401 => unauthorized,
      410 => sessionEnded,
      413 => payloadTooLarge,
      429 => rateLimited,
      >= 500 => internal,
      _ => unknown,
    };
  }
}
