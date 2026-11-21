import 'package:playeroff_cast/src/cast_exception.dart';

/// Lenient readers for the API's JSON: a field of the wrong type reads as
/// absent instead of throwing a cast error far from its cause.
extension JsonReaders on Map<String, Object?> {
  /// A required string; a missing one is a malformed response.
  String string(String key) =>
      stringOrNull(key) ??
      (throw FormatException('PlayerOFF response without "$key"'));

  String? stringOrNull(String key) => switch (this[key]) {
    final String value => value,
    _ => null,
  };

  num? numOrNull(String key) => switch (this[key]) {
    final num value => value,
    _ => null,
  };

  /// A number of seconds, possibly fractional.
  Duration? secondsOrNull(String key) => switch (numOrNull(key)) {
    final num seconds => Duration(milliseconds: (seconds * 1000).round()),
    null => null,
  };

  /// An instant in epoch milliseconds.
  DateTime? epochOrNull(String key) => switch (numOrNull(key)) {
    final num ms => DateTime.fromMillisecondsSinceEpoch(
      ms.round(),
      isUtc: true,
    ),
    null => null,
  };

  Map<String, Object?>? objectOrNull(String key) => switch (this[key]) {
    final Map<String, Object?> value => value,
    _ => null,
  };

  Iterable<Map<String, Object?>> objects(String key) => switch (this[key]) {
    final List<Object?> list => list.whereType<Map<String, Object?>>(),
    _ => const [],
  };
}

/// Runs [read] over a response and reports one that lacks what it should
/// have as what it is for the app: a server that could not be understood.
T readResponse<T>(T Function() read) {
  try {
    return read();
  } on FormatException catch (error) {
    throw CastNetworkException('Unexpected response', cause: error);
  }
}
