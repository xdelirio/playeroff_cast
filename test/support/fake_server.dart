import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A request the fake server received.
final class Received {
  Received(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, String> headers;
  final Object? body;

  @override
  String toString() => '$method $path';
}

/// An event stream the fake server is holding open.
final class OpenStream {
  final _bytes = StreamController<List<int>>();

  /// Whether the client let go of the connection.
  bool get cancelled => _cancelled;
  var _cancelled = false;

  void event(String name, Object? data) =>
      _bytes.add(utf8.encode('event: $name\ndata: ${jsonEncode(data)}\n\n'));

  void ping() => _bytes.add(utf8.encode(': ping\n\n'));

  /// The server closes the connection.
  Future<void> drop() => _bytes.close();
}

typedef Handler = FutureOr<http.Response> Function(Received request);

/// Stands in for the PlayerOFF server: answers by `METHOD /path`, records
/// what it was asked and hands out event streams the test drives.
final class FakeServer {
  FakeServer() {
    client = MockClient.streaming((request, bodyStream) async {
      final text = await bodyStream.bytesToString();
      final received = Received(
        request.method,
        request.url.path,
        request.headers,
        text.isEmpty ? null : jsonDecode(text),
      );
      requests.add(received);

      if (received.path == eventsPath && received.method == 'GET') {
        return _openStream();
      }
      final handler = _handlers['${received.method} ${received.path}'];
      if (handler == null) return _streamed(json(404, error('not_found')));
      return _streamed(await handler(received));
    });
  }

  static const eventsPath = '/v1/sessions/events';

  late final http.Client client;
  final requests = <Received>[];

  /// Every event stream opened so far, oldest first.
  final streams = <OpenStream>[];

  /// What opening the event stream answers instead of a stream, when set.
  http.Response? Function()? refuseStream;

  final _handlers = <String, Handler>{};

  void on(String route, Handler handler) => _handlers[route] = handler;

  /// The requests received for `METHOD /path`.
  List<Received> received(String route) =>
      requests.where((request) => '$request' == route).toList();

  static http.Response json(int status, Object? body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  static Map<String, Object?> error(String code, [String message = 'nope']) => {
    'error': {'code': code, 'message': message},
  };

  http.StreamedResponse _openStream() {
    if (refuseStream?.call() case final refusal?) return _streamed(refusal);
    final stream = OpenStream();
    stream._bytes.onCancel = () => stream._cancelled = true;
    streams.add(stream);
    return http.StreamedResponse(
      stream._bytes.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  static http.StreamedResponse _streamed(http.Response response) =>
      http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
}

/// A `Playback` as the API sends it.
Map<String, Object?> playbackJson({
  String castId = 'cast-1',
  String state = 'playing',
  num position = 10,
  num? duration = 100,
  String? lastCommandId,
}) => {
  'castId': castId,
  'title': 'Film',
  'state': state,
  'position': position,
  'duration': duration,
  'volume': 80,
  'muted': false,
  'subtitles': [
    {'id': '54', 'lang': 'es', 'label': 'Español'},
  ],
  'activeSubtitleId': null,
  'audioTracks': [
    {'id': 'en', 'lang': 'en', 'label': 'English'},
    {'id': 'es', 'lang': 'es', 'label': 'Español'},
  ],
  'activeAudioId': 'en',
  'lastCommandId': ?lastCommandId,
  'updatedAt': 1800000123000,
};
