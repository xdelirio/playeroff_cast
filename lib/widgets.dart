/// Ready-made Flutter widgets over the core: connecting to a TV and
/// controlling what it plays. They draw with the `Theme` around them.
///
/// ```dart
/// final session = await showCastConnectSheet(context, cast: cast);
/// if (session != null) {
///   // …send a video, then:
///   CastRemote(session: session, onEnded: (_) => forget(session));
/// }
/// ```
library;

export 'src/widgets/cast_artwork.dart';
export 'src/widgets/cast_connect_form.dart';
export 'src/widgets/cast_mini_bar.dart';
export 'src/widgets/cast_remote.dart';
export 'src/widgets/cast_session_builder.dart';
export 'src/widgets/cast_strings.dart';
