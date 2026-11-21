import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

/// One message of a Server-Sent Events stream.
@immutable
final class SseMessage {
  const SseMessage(this.event, this.data);

  /// The `event:` field; `message` when the server named none.
  final String event;

  /// The `data:` lines, joined with a line break.
  final String data;

  @override
  String toString() => 'SseMessage($event, $data)';
}

/// Reads a `text/event-stream` body into its messages.
///
/// Comments (the server's `: ping`) and fields other than `event` and `data`
/// are dropped: whoever needs to know the connection is alive watches the
/// bytes, before this.
///
/// Built from transformers rather than an `async*` function on purpose:
/// cancelling a generator that is waiting for its next line does not cancel
/// the connection under it until a line arrives, which on an idle stream is
/// never.
Stream<SseMessage> parseSse(Stream<List<int>> bytes) {
  String? event;
  final data = <String>[];

  return bytes.transform(utf8.decoder).transform(const LineSplitter()).expand((
    line,
  ) {
    if (line.isEmpty) {
      final message = data.isEmpty
          ? null
          : SseMessage(event ?? 'message', data.join('\n'));
      event = null;
      data.clear();
      return [?message];
    }
    if (line.startsWith(':')) return const [];

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.add(value);
    }
    return const [];
  });
}
