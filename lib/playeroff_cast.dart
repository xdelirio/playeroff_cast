/// Send a video to a TV running PlayerOFF and control it: the pure-Dart
/// core, with no Flutter in it.
///
/// ```dart
/// final cast = PlayeroffCast();
/// final session = await cast.connect('K7M3QX');
/// await session.send(CastMedia(url: Uri.parse('https://example.com/film.m3u8')));
/// session.playbackChanges.listen(print);
/// await session.skip(const Duration(seconds: 30));
/// await session.disconnect();
/// ```
library;

export 'src/cast_code.dart';
export 'src/cast_exception.dart';
export 'src/cast_session.dart';
export 'src/cast_timings.dart';
export 'src/models/cast_command.dart';
export 'src/models/cast_event.dart';
export 'src/models/cast_media.dart';
export 'src/models/cast_receiver.dart';
export 'src/models/cast_status.dart';
export 'src/models/playback.dart';
export 'src/playeroff_cast.dart';
