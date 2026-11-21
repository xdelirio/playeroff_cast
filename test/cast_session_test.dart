import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playeroff_cast/playeroff_cast.dart';

import 'support/fake_server.dart';

const _token = 'token-1';

void main() {
  late FakeServer server;
  late PlayeroffCast cast;

  setUp(() {
    server = FakeServer();
    cast = PlayeroffCast(
      baseUrl: Uri.parse('https://cast.test'),
      client: server.client,
    );
    server.on(
      'POST /v1/sessions',
      (_) => FakeServer.json(201, {
        'sessionToken': _token,
        'expiresAt': 1800007200000,
        'receiver': {'platform': 'tizen', 'name': 'Sala'},
      }),
    );
  });

  Matcher apiError(CastErrorCode code) =>
      throwsA(isA<CastApiException>().having((e) => e.code, 'code', code));

  group('connect', () {
    test('redeems the normalized code and returns the session', () async {
      final session = await cast.connect('playeroff://connect?code=k7m3qx');

      expect(server.requests.single.body, {'code': 'K7M3QX'});
      expect(session.token, _token);
      expect(session.receiver.platform, ReceiverPlatform.tizen);
      expect(session.receiver.name, 'Sala');
      expect(
        session.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1800007200000, isUtc: true),
      );
      expect(session.isOver, isFalse);
    });

    test('does not bother the server with text that is not a code', () async {
      await expectLater(
        cast.connect('https://example.com'),
        apiError(CastErrorCode.invalidCode),
      );
      expect(server.requests, isEmpty);
    });

    test('reports a code the server does not know', () async {
      server.on(
        'POST /v1/sessions',
        (_) => FakeServer.json(404, FakeServer.error('invalid_code')),
      );

      await expectLater(
        cast.connect('K7M3QX'),
        apiError(CastErrorCode.invalidCode),
      );
    });

    test('reports too many attempts as retryable', () async {
      server.on(
        'POST /v1/sessions',
        (_) => FakeServer.json(429, FakeServer.error('rate_limited')),
      );

      await expectLater(
        cast.connect('K7M3QX'),
        throwsA(
          isA<CastApiException>()
              .having((e) => e.code, 'code', CastErrorCode.rateLimited)
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.sessionOver, 'sessionOver', isFalse),
        ),
      );
    });

    test('a server that cannot be reached is a network failure', () async {
      final offline = PlayeroffCast(
        baseUrl: Uri.parse('https://cast.test'),
        client: MockClient((_) => throw http.ClientException('no route')),
      );

      await expectLater(
        offline.connect('K7M3QX'),
        throwsA(isA<CastNetworkException>()),
      );
    });

    test('an error page from a proxy still reads as an API error', () async {
      server.on(
        'POST /v1/sessions',
        (_) => http.Response('<html>Bad gateway</html>', 502),
      );

      await expectLater(
        cast.connect('K7M3QX'),
        apiError(CastErrorCode.internal),
      );
    });

    test('keeps a base URL with a path', () async {
      final proxied = PlayeroffCast(
        baseUrl: Uri.parse('https://cast.test/proxy/'),
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://cast.test/proxy/v1/sessions');
          return FakeServer.json(201, {
            'sessionToken': _token,
            'expiresAt': 1,
            'receiver': {'platform': 'web', 'name': ''},
          });
        }),
      );

      expect((await proxied.connect('K7M3QX')).token, _token);
    });
  });

  group('a session', () {
    late CastSession session;

    setUp(() async {
      session = await cast.connect('K7M3QX');
      server.requests.clear();
    });

    test('sends a video with its token', () async {
      server.on(
        'POST /v1/casts',
        (_) => FakeServer.json(202, {
          'castId': 'cast-1',
          'status': 'pending',
          'expiresAt': 1800000300000,
        }),
      );

      final receipt = await session.send(
        CastMedia(url: Uri.parse('https://example.com/a.m3u8'), title: 'Film'),
      );

      final request = server.requests.single;
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.body, {
        'url': 'https://example.com/a.m3u8',
        'title': 'Film',
      });
      expect(receipt.castId, 'cast-1');
      expect(
        receipt.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1800000300000, isUtc: true),
      );
    });

    test('asks for the status of a cast', () async {
      server.on(
        'GET /v1/casts/cast-1',
        (_) => FakeServer.json(200, {
          'castId': 'cast-1',
          'status': 'failed',
          'error': 'unsupported',
        }),
      );

      expect(
        await session.castStatus('cast-1'),
        const CastUpdate(
          castId: 'cast-1',
          status: CastStatus.failed,
          error: 'unsupported',
        ),
      );
    });

    test('sends commands and returns their id', () async {
      server.on(
        'POST /v1/sessions/commands',
        (_) => FakeServer.json(202, {'commandId': 'cmd-1'}),
      );

      expect(await session.skip(const Duration(seconds: 30)), 'cmd-1');
      await session.setSubtitles(null, castId: 'cast-1');
      await session.setVolume(55);

      expect(server.requests.map((r) => r.body), [
        {'type': 'skip', 'seconds': 30.0},
        {'type': 'subtitles', 'trackId': null, 'castId': 'cast-1'},
        {'type': 'volume', 'level': 55},
      ]);
    });

    test('a command with nothing on screen fails without ending it', () async {
      server.on(
        'POST /v1/sessions/commands',
        (_) => FakeServer.json(409, FakeServer.error('nothing_playing')),
      );

      await expectLater(
        session.pause(),
        apiError(CastErrorCode.nothingPlaying),
      );
      expect(session.isOver, isFalse);
    });

    test('fetches what is playing and remembers it', () async {
      server.on(
        'GET /v1/sessions/playback',
        (_) => FakeServer.json(200, {'playback': playbackJson()}),
      );

      final playback = await session.fetchPlayback();

      expect(playback?.state, PlaybackState.playing);
      expect(session.playback, same(playback));
    });

    test('a TV that has played nothing has no playback', () async {
      server.on(
        'GET /v1/sessions/playback',
        (_) => FakeServer.json(200, {'playback': null}),
      );

      expect(await session.fetchPlayback(), isNull);
    });

    for (final (status, code) in [
      (401, 'unauthorized'),
      (410, 'session_ended'),
    ]) {
      test('a $status ends the session for good', () async {
        server.on(
          'POST /v1/casts',
          (_) => FakeServer.json(status, FakeServer.error(code)),
        );
        final media = CastMedia(url: Uri.parse('https://example.com/a.m3u8'));

        await expectLater(
          session.send(media),
          throwsA(
            isA<CastApiException>().having(
              (e) => e.sessionOver,
              'over',
              isTrue,
            ),
          ),
        );
        expect(session.isOver, isTrue);
        expect(await session.over, CastEndReason.unknown);

        // Later calls fail the same way without reaching the server.
        server.requests.clear();
        await expectLater(
          session.send(media),
          apiError(CastErrorCode.sessionEnded),
        );
        expect(server.requests, isEmpty);
      });
    }

    test('an answer missing what it should have is a failure', () async {
      server
        ..on('POST /v1/casts', (_) => FakeServer.json(202, {'status': 'x'}))
        ..on('POST /v1/sessions/commands', (_) => FakeServer.json(202, {}))
        ..on(
          'GET /v1/sessions/playback',
          (_) => FakeServer.json(200, {
            'playback': {'state': 'playing'},
          }),
        );
      final media = CastMedia(url: Uri.parse('https://example.com/a.m3u8'));

      await expectLater(
        session.send(media),
        throwsA(isA<CastNetworkException>()),
      );
      await expectLater(session.pause(), throwsA(isA<CastNetworkException>()));
      await expectLater(
        session.fetchPlayback(),
        throwsA(isA<CastNetworkException>()),
      );
      expect(session.isOver, isFalse);
    });

    test('disconnecting frees the receiver and ends the session', () async {
      server.on('DELETE /v1/sessions', (_) => http.Response('', 204));

      await session.disconnect();

      expect(server.requests.single.toString(), 'DELETE /v1/sessions');
      expect(session.endReason, CastEndReason.disconnected);
      await expectLater(session.events, emitsDone);

      await session.disconnect();
      expect(server.requests, hasLength(1));
    });

    test('disconnecting while offline still closes the session', () async {
      server.on('DELETE /v1/sessions', (_) => throw http.ClientException('x'));

      await session.disconnect();

      expect(session.isOver, isTrue);
    });
  });

  test('a resumed session uses the token it was given', () async {
    server.on(
      'GET /v1/sessions/playback',
      (_) => FakeServer.json(200, {'playback': null}),
    );

    final session = cast.resume('kept-token');
    await session.fetchPlayback();

    expect(
      server.requests.single.headers['Authorization'],
      'Bearer kept-token',
    );
    expect(session.receiver.platform, ReceiverPlatform.unknown);
  });

  group('following the receiver', () {
    /// Runs [body] on a fake clock with a connected session.
    void following(
      void Function(FakeAsync async, CastSession session) body, {
      CastTimings timings = const CastTimings(),
    }) {
      fakeAsync((async) {
        final cast = PlayeroffCast(
          baseUrl: Uri.parse('https://cast.test'),
          client: server.client,
          timings: timings,
          clock: () => async.getClock(DateTime.utc(2026)).now(),
        );
        body(async, cast.resume(_token));
      });
    }

    int polls() => server.received('GET /v1/sessions/playback').length;

    void answerPolls({String state = 'paused'}) => server.on(
      'GET /v1/sessions/playback',
      (_) => FakeServer.json(200, {'playback': playbackJson(state: state)}),
    );

    test('opens no connection until someone listens', () {
      following((async, session) {
        async.flushMicrotasks();
        expect(server.streams, isEmpty);

        session.events.listen((_) {});
        async.flushMicrotasks();
        expect(server.streams, hasLength(1));
        expect(
          server.requests.single.headers['Authorization'],
          'Bearer $_token',
        );
      });
    });

    test('turns the stream into events', () {
      following((async, session) {
        final events = <CastEvent>[];
        session.events.listen(events.add);
        async.flushMicrotasks();

        server.streams.single
          ..event('playback', playbackJson(position: 42))
          ..ping()
          ..event('cast', {'castId': 'cast-1', 'status': 'playing'})
          ..event('playback', null);
        async.flushMicrotasks();

        expect(events, hasLength(3));
        expect(
          (events[0] as PlaybackChanged).playback?.position,
          const Duration(seconds: 42),
        );
        expect(
          (events[1] as CastStatusChanged).update,
          const CastUpdate(castId: 'cast-1', status: CastStatus.playing),
        );
        expect((events[2] as PlaybackChanged).playback, isNull);
        expect(session.playback, isNull);
      });
    });

    test('stamps playback with the time it arrived', () {
      following((async, session) {
        session.playbackChanges.listen((_) {});
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 7));

        server.streams.single.event('playback', playbackJson(position: 10));
        async.flushMicrotasks();

        final playback = session.playback!;
        expect(playback.receivedAt, DateTime.utc(2026, 1, 1, 0, 0, 7));
        expect(
          playback.positionAt(DateTime.utc(2026, 1, 1, 0, 0, 10)),
          const Duration(seconds: 13),
        );
      });
    });

    test('narrows events to playback and to casts', () {
      following((async, session) {
        final states = <PlaybackState?>[];
        final statuses = <CastStatus>[];
        session.playbackChanges.listen((p) => states.add(p?.state));
        session.castUpdates.listen((u) => statuses.add(u.status));
        async.flushMicrotasks();

        // Two listeners, one connection.
        server.streams.single
          ..event('playback', playbackJson(state: 'loading'))
          ..event('cast', {'castId': 'cast-1', 'status': 'delivered'});
        async.flushMicrotasks();

        expect(states, [PlaybackState.loading]);
        expect(statuses, [CastStatus.delivered]);
      });
    });

    test('closes the connection when the last listener leaves', () {
      following((async, session) {
        final first = session.events.listen((_) {});
        final second = session.events.listen((_) {});
        async.flushMicrotasks();

        first.cancel();
        async.flushMicrotasks();
        expect(server.streams.single.cancelled, isFalse);

        second.cancel();
        async.flushMicrotasks();
        expect(server.streams.single.cancelled, isTrue);

        // And stays closed: nothing reconnects behind the app's back.
        async.elapse(const Duration(minutes: 5));
        expect(server.streams, hasLength(1));
        expect(polls(), 0);
      });
    });

    test('listening again opens a new connection', () {
      following((async, session) {
        session.events.listen((_) {}).cancel();
        async.flushMicrotasks();

        session.events.listen((_) {});
        async.flushMicrotasks();

        expect(server.streams, hasLength(2));
        expect(server.streams.last.cancelled, isFalse);
      });
    });

    test('reopens a stream that dropped after working', () {
      following((async, session) {
        session.events.listen((_) {});
        async.flushMicrotasks();
        server.streams.single.event('playback', null);
        async.flushMicrotasks();

        server.streams.single.drop();
        async.elapse(const Duration(seconds: 1));

        expect(server.streams, hasLength(2));
        expect(polls(), 0);
      });
    });

    test('takes a stream that went silent for dead', () {
      following((async, session) {
        session.events.listen((_) {});
        async.flushMicrotasks();
        server.streams.single.event('playback', null);

        // Pings keep it alive…
        for (var i = 0; i < 5; i++) {
          async.elapse(const Duration(seconds: 20));
          server.streams.single.ping();
        }
        async.flushMicrotasks();
        expect(server.streams, hasLength(1));

        // …and without them it is reopened.
        async.elapse(const Duration(seconds: 47));
        expect(server.streams.first.cancelled, isTrue);
        expect(server.streams, hasLength(2));
      });
    });

    test('polls while the stream cannot be opened, then tries it again', () {
      following((async, session) {
        answerPolls();
        server.refuseStream = () =>
            FakeServer.json(429, FakeServer.error('rate_limited'));
        final states = <PlaybackState?>[];
        session.playbackChanges.listen((p) => states.add(p?.state));

        // First window: one poll, then the stream again.
        async.elapse(const Duration(seconds: 2));
        expect(polls(), 1);
        expect(states, [PlaybackState.paused]);
        async.elapse(const Duration(seconds: 1));
        expect(server.received('GET ${FakeServer.eventsPath}'), hasLength(2));

        // Second window is twice as long: two polls before the next try.
        async.elapse(const Duration(seconds: 5, milliseconds: 500));
        expect(polls(), 3);
        async.elapse(const Duration(milliseconds: 500));
        expect(server.received('GET ${FakeServer.eventsPath}'), hasLength(3));

        // Once the stream works, polling stops.
        server.refuseStream = null;
        async.elapse(const Duration(seconds: 12));
        expect(server.streams, hasLength(1));
        server.streams.single.event('playback', null);
        final before = polls();
        async.elapse(const Duration(seconds: 30));
        server.streams.single.ping();
        async.elapse(const Duration(seconds: 30));
        expect(polls(), before);
        expect(server.streams, hasLength(1));
      });
    });

    test('never waits longer than the cap between tries of the stream', () {
      following(
        timings: const CastTimings(maxRetryWindow: Duration(seconds: 6)),
        (async, session) {
          answerPolls();
          server.refuseStream = () => http.Response('', 503);
          session.events.listen((_) {});

          // Windows of 3 s, 6 s, 6 s, 6 s…
          async.elapse(const Duration(seconds: 3 + 6 + 6 + 6));
          expect(server.received('GET ${FakeServer.eventsPath}'), hasLength(5));
        },
      );
    });

    test('a failing poll does not stop the following', () {
      following((async, session) {
        server.refuseStream = () => http.Response('', 503);
        server.on(
          'GET /v1/sessions/playback',
          (_) => throw http.ClientException('offline'),
        );
        final errors = <Object>[];
        session.events.listen((_) {}, onError: errors.add);

        async.elapse(const Duration(seconds: 30));

        expect(errors, isEmpty);
        expect(polls(), greaterThan(3));
        expect(session.isOver, isFalse);
      });
    });

    for (final reason in ['replaced', 'disconnected', 'expired']) {
      test('"$reason" ends the session and closes the stream', () {
        following((async, session) {
          final events = <CastEvent>[];
          var done = false;
          session.events.listen(events.add, onDone: () => done = true);
          async.flushMicrotasks();

          server.streams.single.event('ended', {'reason': reason});
          async.elapse(const Duration(minutes: 1));

          expect((events.single as CastStreamEnded).reason.name, reason);
          expect(done, isTrue);
          expect(session.endReason?.name, reason);
          expect(server.streams.single.cancelled, isTrue);
          expect(server.streams, hasLength(1));
          expect(polls(), 0);
        });
      });
    }

    test('a superseded stream is not reopened; polling takes over', () {
      following((async, session) {
        answerPolls();
        final events = <CastEvent>[];
        session.events.listen(events.add);
        async.flushMicrotasks();

        server.streams.single.event('ended', {'reason': 'superseded'});
        async.elapse(const Duration(minutes: 2));

        expect(session.isOver, isFalse);
        expect(server.streams, hasLength(1));
        expect(
          (events.first as CastStreamEnded).reason,
          CastEndReason.superseded,
        );
        expect(polls(), greaterThan(30));
        expect(events.last, isA<PlaybackChanged>());
      });
    });

    test('a stream refused for a dead token ends the session', () {
      following((async, session) {
        server.refuseStream = () =>
            FakeServer.json(410, FakeServer.error('session_ended'));
        final events = <CastEvent>[];
        session.events.listen(events.add);

        async.elapse(const Duration(minutes: 1));

        expect(
          (events.single as CastStreamEnded).reason,
          CastEndReason.unknown,
        );
        expect(session.isOver, isTrue);
        expect(polls(), 0);
      });
    });

    test('a dead token found while polling ends the session', () {
      following((async, session) {
        server.refuseStream = () => http.Response('', 503);
        server.on(
          'GET /v1/sessions/playback',
          (_) => FakeServer.json(401, FakeServer.error('unauthorized')),
        );
        var done = false;
        session.events.listen((_) {}, onDone: () => done = true);

        async.elapse(const Duration(minutes: 1));

        expect(done, isTrue);
        expect(polls(), 1);
      });
    });

    test('disconnecting closes the stream', () {
      following((async, session) {
        server.on('DELETE /v1/sessions', (_) => http.Response('', 204));
        final events = <CastEvent>[];
        session.events.listen(events.add);
        async.flushMicrotasks();

        unawaited(session.disconnect());
        async.elapse(const Duration(minutes: 1));

        expect(
          (events.single as CastStreamEnded).reason,
          CastEndReason.disconnected,
        );
        expect(server.streams.single.cancelled, isTrue);
        expect(server.streams, hasLength(1));
      });
    });

    test('skips an event it cannot read', () {
      following((async, session) {
        final events = <CastEvent>[];
        session.events.listen(events.add);
        async.flushMicrotasks();

        server.streams.single
          ..event('cast', {'status': 'playing'})
          ..event('playback', {'state': 'playing'})
          ..event('something-new', {'a': 1})
          ..event('playback', playbackJson());
        async.flushMicrotasks();

        expect(events.single, isA<PlaybackChanged>());
      });
    });
  });
}
