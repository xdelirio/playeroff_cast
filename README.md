# playeroff_cast

Send a video to a TV running [PlayerOFF](https://playeroff.app) and control
it from a Flutter app, over the open
[PlayerOFF API](https://playeroff.app/docs/guia/inicio-rapido) (v1.2.0): no
sign-up and no key.

- **Core** (`package:playeroff_cast/playeroff_cast.dart`, pure Dart) —
  `PlayeroffCast` turns the code on the TV into a `CastSession`, which sends
  videos, drives the player and follows it live.

- **Widgets** (`package:playeroff_cast/widgets.dart`) — the connect form
  and sheet, a full remote control and a mini bar. They draw with the
  `Theme` around them and speak English or Spanish with the app's locale.

The receiver side of the API is not here yet.

## Use

```dart
final cast = PlayeroffCast();

// What the person typed, or what the QR holds (playeroff://connect?code=…).
final session = await cast.connect('K7M3QX');

final receipt = await session.send(
  CastMedia(
    url: Uri.parse('https://example.com/film.m3u8'),
    title: 'My film',
    startPosition: const Duration(minutes: 12),
    subtitles: [CastSubtitle(url: Uri.parse('https://example.com/es.vtt'), lang: 'es')],
  ),
);

session.playbackChanges.listen((playback) { /* state, position, tracks */ });
session.castUpdates.listen((update) { /* delivered, playing, failed… */ });

await session.skip(const Duration(seconds: 30), castId: receipt.castId);
await session.setSubtitles(null);
await session.disconnect();
```

## Widgets

```dart
// Asks for the code on the TV; returns the session, or null.
final session = await showCastConnectSheet(
  context,
  cast: cast,
  initialCode: codeFromDeepLink,        // optional: connects right away
  onScanQr: () => openMyQrScanner(),    // optional: the app's own scanner
);

// Poster, title, seek bar, play/pause, ±10 s, volume, audio and subtitle
// tracks, stop and disconnect.
CastRemote(session: session, onEnded: (reason) => forget(session));

// One line with play/pause, for the bottom of other screens.
CastMiniBar(session: session, onTap: openRemote, onEnded: (_) => forget(session));

// Anything else: rebuilds with the TV's playback while it is on screen.
CastSessionBuilder(
  session: session,
  builder: (context, playback) => Text('${session.position}'),
);
```

- There is no theme of their own: colours, shapes and type come from
  `Theme.of(context)`.
- `CastConnectForm` is the sheet's content, for a dialog or a page.
- The connect form is headed by PlayerOFF's mark (`PlayeroffLogo`), the one
  on the TV's screen; the button that opens it is the app's, usually a plain
  cast icon.
- The poster is the one of the video this session sent
  (`session.sentMedia`): the API does not report it, so a video sent from
  another phone shows a placeholder.
- Loading and buffering show as a spinner over the poster, so the controls
  never move while a video stalls and recovers.
- The QR scanner is the app's (`onScanQr`): this package brings no camera
  nor permissions. The TV's QR is light on dark; some scanners need inverted
  reading turned on.
- A command the TV refuses is told in a snack bar when there is a `Scaffold`
  above. A session that ends is told to the app through `onEnded`.
- The event stream is open only while one of these widgets is on screen.
- For a look of the app's own, build on the parts these widgets are made
  of: `CastSessionBuilder` (live state), `CastArtwork` (poster),
  `CastStrings` (words, `formatCastDuration`) and `sendCastCommand` (runs a
  command, tells the person when it is refused). The `CastSession` is the
  controller: state, commands and streams.
- `example/` is an app that connects, sends a video and shows the remote.

## What it takes care of

- **The code.** `CastCode.parse` reads a typed code (`k7m 3qx`) or the QR's
  link; `CastCode.isComplete` tells when a typed one is whole.
- **Following the TV.** `session.events` opens the event stream with its
  first listener and closes it with the last. A dropped stream is reopened;
  while it is down playback is polled every 3 s, and the stream is tried
  again after 3, 6, 12… up to 60 s. A stream that goes 45 s without a byte
  (the server pings every 20 s) is taken for dead.
- **The seek bar.** The TV reports every 5 s while playing;
  `playback.positionAt(DateTime.now())` gives the position in between.
- **The end of a session.** A `401`/`410` on any call, or an `ended` event,
  marks the session as over: `session.isOver`, `session.over`, and a final
  `CastStreamEnded` on `events`. Only a new code brings a new one.
- **Errors.** `CastApiException` (with a `CastErrorCode`, `sessionOver` and
  `retryable`) or `CastNetworkException`. The API's messages are in Spanish
  and meant for logs; pick the app's own text from the code.
- **Restarts.** Keep `session.token` (a credential) and `session.receiver`,
  and hand them to `cast.resume`.

## Worth knowing

- One phone per TV: connecting ends the session of whoever was connected.
- A new cast replaces the current one; there is no queue.
- `CastMedia.headers` are applied only by the Android TV receiver
  (`session.receiver.appliesHeaders`).
- The default server is `https://playeroff.app` (the guide's examples say
  `beta.playeroff.app`; the real one has no `beta`). Pass `baseUrl` for
  another. A code only works on the server that issued it.

## Checking against the real server

```sh
flutter test                    # fake server, no network
dart run tool/live_check.dart   # the real one; the script plays the TV
```
