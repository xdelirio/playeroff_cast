import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:playeroff_cast/playeroff_cast.dart';
import 'package:playeroff_cast/widgets.dart';

import 'support/fake_server.dart';

const _strings = CastStrings.en();
const _token = 'token-1';

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer()
      ..on(
        'POST /v1/sessions',
        (_) => FakeServer.json(201, {
          'sessionToken': _token,
          'expiresAt': 1800007200000,
          'receiver': {'platform': 'tizen', 'name': ''},
        }),
      )
      ..on(
        'POST /v1/sessions/commands',
        (_) => FakeServer.json(202, {'commandId': 'cmd-1'}),
      )
      ..on('DELETE /v1/sessions', (_) => http.Response('', 204));
  });

  /// A client on the test's own clock, so positions move with `pump`.
  PlayeroffCast castFor(WidgetTester tester) => PlayeroffCast(
    baseUrl: Uri.parse('https://cast.test'),
    client: server.client,
    clock: () => tester.binding.clock.now(),
  );

  Future<void> show(WidgetTester tester, Widget child) {
    // Tall enough for the whole remote: a tap needs its target on screen.
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  /// Lets requests and stream events run their course.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  /// Takes the widgets down so the session lets go of its connection.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  List<Object?> commands() => [
    for (final request in server.received('POST /v1/sessions/commands'))
      request.body,
  ];

  group('CastStrings', () {
    test('speaks Spanish to Spanish locales and English to the rest', () {
      expect(
        CastStrings.forLocale(const Locale('es', 'MX')).connect,
        const CastStrings.es().connect,
      );
      expect(
        CastStrings.forLocale(const Locale('fr')).connect,
        _strings.connect,
      );
      expect(CastStrings.forLocale(null).connect, _strings.connect);
    });

    test('names a receiver by its kind when it has no name', () {
      expect(
        _strings.receiverName(
          const CastReceiver(platform: ReceiverPlatform.webos),
        ),
        _strings.tvLg,
      );
      expect(
        _strings.receiverName(
          const CastReceiver(platform: ReceiverPlatform.webos, name: ' Sala '),
        ),
        'Sala',
      );
    });

    test('names a track by its language when it has no label', () {
      expect(
        _strings.trackName(const CastTrack(id: '1', lang: 'es', label: '')),
        'ES',
      );
    });

    test('formats durations with hours only when there are any', () {
      expect(formatCastDuration(const Duration(seconds: 125)), '2:05');
      expect(formatCastDuration(const Duration(seconds: 3725)), '1:02:05');
      expect(formatCastDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  testWidgets('the logo is drawn from the package at the asked height', (
    tester,
  ) async {
    await tester.pumpWidget(const Center(child: PlayeroffLogo(size: 32)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PlayeroffLogo)).height, 32);
  });

  group('CastConnectForm', () {
    Finder connectButton() =>
        find.widgetWithText(FilledButton, _strings.connect);

    bool enabled(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
        null;

    testWidgets('connects with the typed code', (tester) async {
      CastSession? connected;
      await show(
        tester,
        CastConnectForm(
          cast: castFor(tester),
          onConnected: (session) => connected = session,
        ),
      );
      expect(enabled(tester), isFalse);
      expect(find.text(_strings.scanQr), findsNothing);

      await tester.enterText(find.byType(TextField), 'k7m-3q');
      await tester.pump();
      expect(find.text('K7M3Q'), findsOneWidget);
      expect(enabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), 'k7m 3qx');
      await tester.pump();
      await tester.tap(connectButton());
      await settle(tester);

      expect(server.requests.single.body, {'code': 'K7M3QX'});
      expect(connected?.token, _token);
    });

    testWidgets('says so when the code is not accepted', (tester) async {
      server.on(
        'POST /v1/sessions',
        (_) => FakeServer.json(404, FakeServer.error('invalid_code')),
      );
      var connected = false;
      await show(
        tester,
        CastConnectForm(
          cast: castFor(tester),
          onConnected: (_) => connected = true,
        ),
      );

      await tester.enterText(find.byType(TextField), 'K7M3QX');
      await tester.pump();
      await tester.tap(connectButton());
      await settle(tester);

      expect(find.text(_strings.errorInvalidCode), findsOneWidget);
      expect(connected, isFalse);
      expect(enabled(tester), isTrue);

      // Correcting the code clears the complaint.
      await tester.enterText(find.byType(TextField), 'K7M3Q');
      await tester.pump();
      expect(find.text(_strings.errorInvalidCode), findsNothing);
    });

    testWidgets('connects by itself with a code it was given', (tester) async {
      CastSession? connected;
      await show(
        tester,
        CastConnectForm(
          cast: castFor(tester),
          initialCode: 'playeroff://connect?code=k7m3qx',
          onConnected: (session) => connected = session,
        ),
      );
      await settle(tester);

      expect(server.requests.single.body, {'code': 'K7M3QX'});
      expect(connected, isNotNull);
    });

    testWidgets('connects with what the scanner read', (tester) async {
      CastSession? connected;
      await show(
        tester,
        CastConnectForm(
          cast: castFor(tester),
          onScanQr: () async => 'playeroff://connect?code=K7M3QX',
          onConnected: (session) => connected = session,
        ),
      );

      await tester.tap(find.text(_strings.scanQr));
      await settle(tester);

      expect(server.requests.single.body, {'code': 'K7M3QX'});
      expect(connected, isNotNull);
    });

    testWidgets('a QR that is not a TV code asks nothing of the server', (
      tester,
    ) async {
      await show(
        tester,
        CastConnectForm(
          cast: castFor(tester),
          onScanQr: () async => 'https://example.com/menu',
          onConnected: (_) {},
        ),
      );

      await tester.tap(find.text(_strings.scanQr));
      await settle(tester);

      expect(find.text(_strings.errorInvalidCode), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('a scanner the person backed out of changes nothing', (
      tester,
    ) async {
      await show(
        tester,
        CastConnectForm(
          cast: castFor(tester),
          onScanQr: () async => null,
          onConnected: (_) {},
        ),
      );

      await tester.tap(find.text(_strings.scanQr));
      await settle(tester);

      expect(server.requests, isEmpty);
      expect(find.text(_strings.errorInvalidCode), findsNothing);
    });

    testWidgets('the sheet returns the session', (tester) async {
      final cast = castFor(tester);
      CastSession? result;
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showCastConnectSheet(context, cast: cast),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'K7M3QX');
      await tester.pump();
      await tester.tap(connectButton());
      await tester.pumpAndSettle();

      expect(result?.token, _token);
      expect(find.byType(CastConnectForm), findsNothing);
    });
  });

  group('CastRemote', () {
    late CastSession session;

    Future<void> open(
      WidgetTester tester, {
      ValueChanged<CastEndReason>? onEnded,
      VoidCallback? onDisconnected,
    }) async {
      session = castFor(tester).resume(
        _token,
        receiver: const CastReceiver(
          platform: ReceiverPlatform.tizen,
          name: 'Sala',
        ),
      );
      await show(
        tester,
        CastRemote(
          session: session,
          onEnded: onEnded,
          onDisconnected: onDisconnected,
        ),
      );
      await settle(tester);
    }

    Future<void> report(
      WidgetTester tester,
      Map<String, Object?>? playback,
    ) async {
      server.streams.last.event('playback', playback);
      await settle(tester);
    }

    testWidgets('shows the receiver and that nothing plays yet', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Connected to Sala'), findsOneWidget);
      expect(find.text(_strings.nothingPlaying), findsOneWidget);
      expect(find.text(_strings.stop), findsNothing);
      expect(find.byType(Slider), findsNothing);

      await report(tester, playbackJson(state: 'stopped'));
      expect(find.text(_strings.nothingPlaying), findsOneWidget);

      await close(tester);
    });

    testWidgets('shows what plays and pauses it', (tester) async {
      await open(tester);
      await report(tester, playbackJson(position: 10, duration: 100));

      expect(find.text('Film'), findsOneWidget);
      expect(find.text('0:10'), findsOneWidget);
      expect(find.text('1:40'), findsOneWidget);

      await tester.tap(find.byTooltip(_strings.pause));
      await settle(tester);

      expect(commands(), [
        {'type': 'pause', 'castId': 'cast-1'},
      ]);
      await close(tester);
    });

    testWidgets('the position moves on between reports', (tester) async {
      await open(tester);
      await report(tester, playbackJson(position: 10, duration: 100));

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:13'), findsOneWidget);

      // And stands still once paused.
      await report(tester, playbackJson(state: 'paused', position: 13));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('0:13'), findsOneWidget);

      await close(tester);
    });

    testWidgets('the controls do not move when the status comes and goes', (
      tester,
    ) async {
      await open(tester);
      final positions = <String, Offset>{};

      for (final state in ['playing', 'buffering', 'paused', 'loading']) {
        await report(tester, playbackJson(state: state));
        positions[state] = tester.getTopLeft(find.byTooltip(_strings.rewind));
      }

      // Loading shows as a spinner over the poster, not as a line of text.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_strings.stateLoading), findsNothing);
      expect(positions.values.toSet(), hasLength(1), reason: '$positions');
      await close(tester);
    });

    testWidgets('resumes a paused video and restarts an ended one', (
      tester,
    ) async {
      await open(tester);

      for (final state in ['paused', 'ended']) {
        await report(tester, playbackJson(state: state));
        await tester.tap(find.byTooltip(_strings.play));
        await settle(tester);
      }

      expect(commands(), [
        {'type': 'play', 'castId': 'cast-1'},
        {'type': 'play', 'castId': 'cast-1'},
      ]);
      expect(find.text(_strings.stateEnded), findsOneWidget);
      await close(tester);
    });

    testWidgets('skips, stops and mutes', (tester) async {
      await open(tester);
      await report(tester, playbackJson());

      for (final tooltip in [
        _strings.rewind,
        _strings.forward,
        _strings.mute,
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await settle(tester);
      }
      await tester.tap(find.text(_strings.stop));
      await settle(tester);

      expect(commands(), [
        {'type': 'skip', 'seconds': -10.0, 'castId': 'cast-1'},
        {'type': 'skip', 'seconds': 10.0, 'castId': 'cast-1'},
        {'type': 'mute', 'muted': true, 'castId': 'cast-1'},
        {'type': 'stop', 'castId': 'cast-1'},
      ]);
      await close(tester);
    });

    testWidgets('seeks where the bar is dragged to', (tester) async {
      await open(tester);
      await report(tester, playbackJson(state: 'paused', position: 0));

      final slider = find.byType(Slider).first;
      await tester.tapAt(tester.getCenter(slider));
      await settle(tester);

      final seek = commands().single! as Map<String, Object?>;
      expect(seek['type'], 'seek');
      expect(seek['position'], closeTo(50, 2));
      // The thumb stays where it was put until the TV reports.
      expect(find.text('0:00'), findsNothing);

      await report(tester, playbackJson(state: 'paused', position: 50));
      expect(find.text('0:50'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a refused seek puts the bar back where the video is', (
      tester,
    ) async {
      server.on(
        'POST /v1/sessions/commands',
        (_) => FakeServer.json(409, FakeServer.error('nothing_playing')),
      );
      await open(tester);
      await report(tester, playbackJson(state: 'paused', position: 0));

      await tester.tapAt(tester.getCenter(find.byType(Slider).first));
      await settle(tester);

      expect(find.text('0:00'), findsOneWidget);
      await close(tester);
    });

    testWidgets('sets the volume', (tester) async {
      await open(tester);
      await report(tester, playbackJson());

      final slider = find.byType(Slider).last;
      await tester.tapAt(tester.getCenter(slider));
      await settle(tester);

      final volume = commands().single! as Map<String, Object?>;
      expect(volume['type'], 'volume');
      expect(volume['level'], closeTo(50, 3));
      await close(tester);
    });

    testWidgets('picks a subtitle track, and turns them off', (tester) async {
      await open(tester);
      await report(tester, playbackJson());
      expect(find.widgetWithText(OutlinedButton, _strings.off), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cast-subtitles')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Español'));
      await tester.pumpAndSettle();

      await report(tester, {...playbackJson(), 'activeSubtitleId': '54'});
      expect(find.widgetWithText(OutlinedButton, 'Español'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cast-subtitles')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, _strings.off));
      await tester.pumpAndSettle();

      expect(commands(), [
        {'type': 'subtitles', 'trackId': '54', 'castId': 'cast-1'},
        {'type': 'subtitles', 'trackId': null, 'castId': 'cast-1'},
      ]);
      await close(tester);
    });

    testWidgets('picking the track already on, or none, sends nothing', (
      tester,
    ) async {
      await open(tester);
      await report(tester, playbackJson());

      await tester.tap(find.byKey(const ValueKey('cast-audio')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'English'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cast-audio')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(commands(), isEmpty);
      await close(tester);
    });

    testWidgets('switches the audio track', (tester) async {
      await open(tester);
      await report(tester, playbackJson());

      await tester.tap(find.byKey(const ValueKey('cast-audio')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Español'));
      await tester.pumpAndSettle();

      expect(commands(), [
        {'type': 'audio', 'trackId': 'es', 'castId': 'cast-1'},
      ]);
      await close(tester);
    });

    testWidgets('offers no track choice when there is none to make', (
      tester,
    ) async {
      await open(tester);
      await report(tester, {
        ...playbackJson(),
        'subtitles': <Object?>[],
        'audioTracks': [
          {'id': 'en', 'lang': 'en', 'label': 'English'},
        ],
      });

      expect(find.byKey(const ValueKey('cast-subtitles')), findsNothing);
      expect(find.byKey(const ValueKey('cast-audio')), findsNothing);
      await close(tester);
    });

    testWidgets('shows the poster of the video it sent', (tester) async {
      server.on(
        'POST /v1/casts',
        (_) => FakeServer.json(202, {
          'castId': 'cast-1',
          'status': 'pending',
          'expiresAt': 1800000300000,
        }),
      );
      await open(tester);
      expect(find.byType(Image), findsNothing);

      await session.send(
        CastMedia(
          url: Uri.parse('https://example.com/a.m3u8'),
          title: 'Sent title',
          poster: Uri.parse('https://example.com/poster.jpg'),
        ),
      );
      await report(tester, {...playbackJson(), 'title': ''});

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://example.com/poster.jpg',
      );
      // The TV reported no title: the one that was sent stands in.
      expect(find.text('Sent title'), findsOneWidget);
      expect(find.text('Casting to Sala'), findsOneWidget);

      // A video someone else sent has neither.
      await report(tester, {...playbackJson(castId: 'theirs'), 'title': ''});
      expect(find.byType(Image), findsNothing);
      expect(find.text(_strings.untitled), findsOneWidget);
      await close(tester);
    });

    testWidgets('a live video has no seek bar', (tester) async {
      await open(tester);
      await report(tester, playbackJson(duration: null));

      expect(find.text(_strings.live), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      await close(tester);
    });

    testWidgets('says why the TV could not play it', (tester) async {
      await open(tester);
      await report(tester, {
        ...playbackJson(state: 'failed'),
        'error': 'unsupported',
      });

      expect(find.text(_strings.failedUnsupported), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.play_arrow),
            )
            .onPressed,
        isNull,
      );
      await close(tester);
    });

    testWidgets('tells when the TV refuses a command', (tester) async {
      server.on(
        'POST /v1/sessions/commands',
        (_) => FakeServer.json(409, FakeServer.error('cast_mismatch')),
      );
      await open(tester);
      await report(tester, playbackJson());

      await tester.tap(find.byTooltip(_strings.pause));
      await settle(tester);

      expect(find.text(_strings.errorCastMismatch), findsOneWidget);
      await close(tester);
    });

    testWidgets('tells the app when the TV ends the session', (tester) async {
      final ended = <CastEndReason>[];
      await open(tester, onEnded: ended.add);

      server.streams.single.event('ended', {'reason': 'replaced'});
      await settle(tester);

      expect(ended, [CastEndReason.replaced]);
      await close(tester);
    });

    testWidgets('disconnects', (tester) async {
      final ended = <CastEndReason>[];
      var disconnected = 0;
      await open(
        tester,
        onEnded: ended.add,
        onDisconnected: () => disconnected++,
      );

      await tester.tap(find.text(_strings.disconnect));
      await settle(tester);

      expect(server.received('DELETE /v1/sessions'), hasLength(1));
      expect(ended, [CastEndReason.disconnected]);
      expect(disconnected, 1);
      await close(tester);
    });

    testWidgets('holds the connection only while on screen', (tester) async {
      await open(tester);
      expect(server.streams.single.cancelled, isFalse);

      await close(tester);
      expect(server.streams.single.cancelled, isTrue);
    });

    testWidgets('a session that was already over is reported, not followed', (
      tester,
    ) async {
      final over = castFor(tester).resume(_token);
      await over.disconnect();
      final ended = <CastEndReason>[];

      await show(tester, CastRemote(session: over, onEnded: ended.add));
      await settle(tester);

      expect(ended, [CastEndReason.disconnected]);
      expect(server.streams, isEmpty);
    });
  });

  group('CastMiniBar', () {
    testWidgets('sums up what plays, toggles it and opens on tap', (
      tester,
    ) async {
      final session = castFor(tester).resume(
        _token,
        receiver: const CastReceiver(platform: ReceiverPlatform.android),
      );
      var taps = 0;
      await show(tester, CastMiniBar(session: session, onTap: () => taps++));
      await settle(tester);

      expect(find.text(_strings.nothingPlaying), findsOneWidget);
      expect(find.text(_strings.tvAndroid), findsOneWidget);

      server.streams.single.event(
        'playback',
        playbackJson(position: 25, duration: 100),
      );
      await settle(tester);

      expect(find.text('Film'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(0.25, 0.01),
      );

      await tester.tap(find.byTooltip(_strings.pause));
      await settle(tester);
      expect(commands(), [
        {'type': 'pause', 'castId': 'cast-1'},
      ]);

      await tester.tap(find.text('Film'));
      expect(taps, 1);
      await close(tester);
    });
  });
}
