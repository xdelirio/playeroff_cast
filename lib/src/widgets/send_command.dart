import 'package:flutter/material.dart';
import 'package:playeroff_cast/playeroff_cast.dart';
import 'package:playeroff_cast/src/widgets/cast_strings.dart';

/// Runs [command] and tells the person, in a snack bar, when the TV refused
/// it. Nothing is shown without a `Scaffold` above.
///
/// A session that ended is not told here: the app hears of it through the
/// widgets' `onEnded` and decides what to say.
///
/// Returns whether the TV took the command.
Future<bool> sendCastCommand(
  BuildContext context,
  Future<Object?> Function() command,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = CastStrings.of(context);
  try {
    await command();
    return true;
  } on CastException catch (error) {
    if (error is! CastApiException || !error.sessionOver) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.error(error))));
    }
    return false;
  }
}
