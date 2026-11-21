// Checks the client against the real server, end to end, with no TV: this
// script plays the receiver's part through the receiver endpoints.
//
//   dart run tool/live_check.dart [baseUrl]
//
// It creates a temporary receiver on the server, which expires by itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:playeroff_cast/playeroff_cast.dart';

Future<void> main(List<String> args) async {
  final baseUrl = args.isEmpty
      ? PlayeroffCast.defaultBaseUrl
      : Uri.parse(args.first);
  final client = http.Client();
  final cast = PlayeroffCast(baseUrl: baseUrl, client: client);

  Future<Object?> tv(
    String method,
    String path, {
    Object? body,
    String? secret,
  }) async {
    final request = http.Request(method, baseUrl.resolve(path))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-Receiver-Secret': ?secret,
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await client.send(request));
    if (response.statusCode >= 400) {
      throw StateError(
        '$method $path → ${response.statusCode} ${response.body}',
      );
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  void step(String text) => stdout.writeln('✓ $text');

  try {
    final created =
        await tv(
              'POST',
              '/v1/receivers',
              body: {'platform': 'web', 'name': 'live_check'},
            )
            as Map<String, Object?>;
    final id = created['receiverId']! as String;
    final secret = created['receiverSecret']! as String;
    final code = (created['state']! as Map<String, Object?>)['code']! as String;
    step('receiver created, showing a code');

    final session = await cast.connect(
      'playeroff://connect?code=${code.toLowerCase()}',
    );
    step('connected: ${session.receiver}');

    final events = <CastEvent>[];
    final subscription = session.events.listen(events.add);
    Future<void> until(bool Function() test, String Function() what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!test()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('never saw: ${what()}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      step(what());
    }

    await until(
      () => events.whereType<PlaybackChanged>().isNotEmpty,
      () => 'event stream open, first playback is ${session.playback}',
    );

    final receipt = await session.send(
      CastMedia(
        url: Uri.parse('https://example.com/film.m3u8'),
        title: 'Live check',
        startPosition: const Duration(seconds: 90),
        headers: const {'Referer': 'https://example.com/'},
      ),
    );
    step('cast accepted: ${receipt.castId}');
    step(
      'status by GET: ${(await session.castStatus(receipt.castId)).status.name}',
    );

    final state =
        await tv('GET', '/v1/receivers/$id/state', secret: secret)
            as Map<String, Object?>;
    final pending = state['pendingCast'] as Map<String, Object?>?;
    if (pending?['castId'] != receipt.castId) {
      throw StateError('TV did not get the cast: $state');
    }
    step('the TV sees the cast (startPosition ${pending?['startPosition']})');

    Map<String, Object?> report(
      String playbackState,
      num position, {
      String? lastCommandId,
    }) => {
      'castId': receipt.castId,
      'title': 'Live check',
      'state': playbackState,
      'position': position,
      'duration': 600,
      'volume': 70,
      'muted': false,
      'subtitles': [
        {'id': 's1', 'lang': 'es', 'label': 'Español'},
      ],
      'activeSubtitleId': 's1',
      'audioTracks': [
        {'id': 'a1', 'lang': 'en', 'label': 'English'},
      ],
      'activeAudioId': 'a1',
      'lastCommandId': ?lastCommandId,
    };

    await tv(
      'PUT',
      '/v1/receivers/$id/playback',
      body: report('playing', 90),
      secret: secret,
    );
    await until(
      () => session.playback?.state == PlaybackState.playing,
      () =>
          'playback event: ${session.playback}, subtitle ${session.playback?.activeSubtitle}',
    );
    await until(
      () => events.whereType<CastStatusChanged>().any(
        (e) => e.update.status == CastStatus.playing,
      ),
      () => 'cast event: playing',
    );

    final commandId = await session.skip(
      const Duration(seconds: 30),
      castId: receipt.castId,
    );
    final after =
        await tv('GET', '/v1/receivers/$id/state', secret: secret)
            as Map<String, Object?>;
    final commands = (after['commands']! as List).cast<Map<String, Object?>>();
    if (!commands.any(
      (c) =>
          c['commandId'] == commandId &&
          c['type'] == 'skip' &&
          c['seconds'] == 30,
    )) {
      throw StateError('TV did not get the command: $commands');
    }
    step('command reached the TV: $commandId');

    await session.setSubtitles(null);
    await session.setVolume(40);
    await session.seek(const Duration(minutes: 2));
    step('subtitles off, volume and seek accepted');

    await tv(
      'PUT',
      '/v1/receivers/$id/playback',
      body: report('paused', 120, lastCommandId: commandId),
      secret: secret,
    );
    await until(
      () => session.playback?.lastCommandId == commandId,
      () => 'playback carries lastCommandId (${session.playback?.state.name})',
    );

    try {
      await session.pause(castId: 'another-cast');
      throw StateError('a command for another cast was accepted');
    } on CastApiException catch (error) {
      step('command for another cast refused: ${error.code.name}');
    }

    await session.disconnect();
    await subscription.cancel();
    step('disconnected (${session.endReason?.name})');

    try {
      await cast.resume(session.token).fetchPlayback();
      throw StateError('the token still works after disconnecting');
    } on CastApiException catch (error) {
      step('the old token is refused: ${error.statusCode} ${error.code.name}');
    }

    try {
      await cast.connect('ZZZZZZ');
    } on CastApiException catch (error) {
      step('a made-up code is refused: ${error.code.name}');
    }
    stdout.writeln('\nAll good against $baseUrl');
  } finally {
    client.close();
  }
}
