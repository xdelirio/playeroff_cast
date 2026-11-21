/// Ready-made Flutter widgets over the core: connecting to a TV and
/// controlling what it plays. They draw with the `Theme` around them.
///
/// An app that wants its own look builds it from the same parts these are
/// made of: [CastSessionBuilder] for the live state, [CastArtwork] for the
/// poster, [CastStrings] for the words and [sendCastCommand] to run a
/// command and tell the person when it is refused. The session itself is
/// the controller.
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
export 'src/widgets/playeroff_logo.dart';
export 'src/widgets/send_command.dart';
