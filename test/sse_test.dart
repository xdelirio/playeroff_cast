import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playeroff_cast/src/transport/sse.dart';

Future<List<SseMessage>> _parse(List<String> chunks) =>
    parseSse(Stream.fromIterable(chunks.map(utf8.encode))).toList();

void main() {
  test('reads named events with their data', () async {
    final messages = await _parse([
      'event: playback\ndata: {"a":1}\n\n',
      'event: cast\ndata: {"b":2}\n\n',
    ]);

    expect(messages.map((m) => (m.event, m.data)), [
      ('playback', '{"a":1}'),
      ('cast', '{"b":2}'),
    ]);
  });

  test('puts back together an event split across chunks', () async {
    final messages = await _parse([
      'event: play',
      'back\ndata: {"a"',
      ':1}\n',
      '\n',
    ]);

    expect(messages.single.event, 'playback');
    expect(messages.single.data, '{"a":1}');
  });

  test('skips the pings', () async {
    final messages = await _parse([': ping\n\n', 'data: 1\n\n', ': ping\n\n']);

    expect(messages.single.data, '1');
  });

  test('an event without a name is a message', () async {
    expect((await _parse(['data: hi\n\n'])).single.event, 'message');
  });

  test('joins the lines of a multi-line data', () async {
    expect((await _parse(['data: a\ndata: b\n\n'])).single.data, 'a\nb');
  });

  test('the name of one event does not leak into the next', () async {
    final messages = await _parse(['event: cast\ndata: 1\n\n', 'data: 2\n\n']);

    expect(messages.map((m) => m.event), ['cast', 'message']);
  });

  test('accepts CRLF line endings', () async {
    final messages = await _parse(['event: cast\r\ndata: 1\r\n\r\n']);

    expect(messages.single.event, 'cast');
  });

  test('drops an event the connection cut short', () async {
    expect(await _parse(['event: cast\ndata: 1\n']), isEmpty);
  });
}
