/// The code a receiver shows on screen, as typed by a person or read from
/// its QR.
///
/// The server already forgives case, spaces and hyphens; this exists so an
/// app can accept a scanned QR and a typed code through the same door, and
/// know when a typed code is complete without a round trip.
abstract final class CastCode {
  /// How many characters a code has today.
  static const length = 6;

  /// The characters a code is made of: no `0`/`O` nor `1`/`I`/`L`, which
  /// look alike on a TV across the room.
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// The scheme and host of the QR: `playeroff://connect?code=K7M3QX`.
  static const qrScheme = 'playeroff';
  static const qrHost = 'connect';

  /// The code inside [input], upper-cased and without separators, or null
  /// when there is none.
  ///
  /// [input] is either the QR's content or what a person typed
  /// (`k7m 3qx`, `K7M-3QX`). Length and alphabet are not enforced here — the
  /// server decides what a valid code is — see [isComplete] for that.
  static String? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme.toLowerCase() == qrScheme) {
      if (uri.host.toLowerCase() != qrHost) return null;
      final code = uri.queryParameters['code'];
      return code == null ? null : _normalize(code);
    }
    return _normalize(text);
  }

  /// The code of a scanned QR or an incoming `playeroff://` deep link, or
  /// null when [uri] is something else.
  static String? fromUri(Uri uri) =>
      uri.scheme.toLowerCase() == qrScheme ? parse(uri.toString()) : null;

  /// Whether [code] has the shape of today's codes. Meant for enabling a
  /// "connect" button while typing, not for rejecting a scanned code.
  static bool isComplete(String code) {
    final normalized = _normalize(code);
    return normalized != null &&
        normalized.length == length &&
        normalized.split('').every(alphabet.contains);
  }

  static String? _normalize(String raw) {
    final code = raw.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    return code.isEmpty || !RegExp(r'^[A-Z0-9]+$').hasMatch(code) ? null : code;
  }
}
