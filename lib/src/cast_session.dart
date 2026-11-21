import 'dart:async';
import 'dart:convert';

import 'package:playeroff_cast/src/cast_exception.dart';
import 'package:playeroff_cast/src/cast_timings.dart';
import 'package:playeroff_cast/src/models/cast_command.dart';
import 'package:playeroff_cast/src/models/cast_event.dart';
import 'package:playeroff_cast/src/models/cast_media.dart';
import 'package:playeroff_cast/src/models/cast_receiver.dart';
import 'package:playeroff_cast/src/models/cast_status.dart';
import 'package:playeroff_cast/src/models/json.dart';
import 'package:playeroff_cast/src/models/playback.dart';
import 'package:playeroff_cast/src/transport/cast_transport.dart';
import 'package:playeroff_cast/src/transport/sse.dart';

/// A connection to one receiver: sends videos to it, drives its player and
/// follows what it plays.
///
/// A session lasts 2 hours since its last request (or for as long as
/// [events] is listened to), and ends early when the TV is closed or someone
/// else connects to it. Once it is over ([isOver]) every call fails with a
/// [CastApiException] whose `sessionOver` is true, and only a new code
/// brings a new one.
final class CastSession {
  CastSession({
    required CastTransport transport,
    required this.token,
    required this.receiver,
    required CastTimings timings,
    required DateTime Function() clock,
    this.expiresAt,
  }) : _transport = transport,
       _timings = timings,
       _clock = clock,
       _auth = SessionAuth(token) {
    _events = StreamController<CastEvent>.broadcast(
      onListen: _startFollowing,
      onCancel: _stopFollowing,
    );
  }

  final CastTransport _transport;
  final CastTimings _timings;
  final DateTime Function() _clock;
  final SessionAuth _auth;

  /// What identifies this session to the server. An app that wants to
  /// survive a restart keeps it (it is a credential: store it as one) and
  /// hands it to `PlayeroffCast.resume`.
  final String token;

  final CastReceiver receiver;

  /// When the session expired as of connecting; every request pushes it
  /// back, so it is only a lower bound.
  final DateTime? expiresAt;

  late final StreamController<CastEvent> _events;
  final _over = Completer<CastEndReason>();
  Playback? _playback;
  CastEndReason? _endReason;
  ({String castId, CastMedia media})? _sent;

  /// Bumped every time following stops, so a loop that was mid-await when it
  /// happened can tell it is no longer the current one.
  int _generation = 0;
  StreamSubscription<SseMessage>? _stream;
  void Function()? _interrupt;

  /// The last playback state heard of, by any means; null until the first
  /// one arrives or while the TV has not played anything.
  Playback? get playback => _playback;

  /// Where the video is right now: the last reported position, moved on by
  /// the time since if it is playing. Null with no [playback].
  Duration? get position => _playback?.positionAt(_clock());

  /// Whether the session is gone for good.
  bool get isOver => _endReason != null;

  /// Why the session ended, once it has.
  CastEndReason? get endReason => _endReason;

  /// Completes when the session ends, with the reason.
  Future<CastEndReason> get over => _over.future;

  /// What happens on the receiver, live.
  ///
  /// The connection is opened by the first listener and closed when the last
  /// one leaves. A dropped connection is reopened by itself, and while it is
  /// down playback is asked for every few seconds instead, so listeners only
  /// ever notice a delay. The stream closes after a [CastStreamEnded] whose
  /// reason ends the session.
  Stream<CastEvent> get events => _events.stream;

  /// [events] narrowed to the player's state.
  Stream<Playback?> get playbackChanges => events
      .where((event) => event is PlaybackChanged)
      .map((event) => (event as PlaybackChanged).playback);

  /// [events] narrowed to the progress of this session's casts.
  Stream<CastUpdate> get castUpdates => events
      .where((event) => event is CastStatusChanged)
      .map((event) => (event as CastStatusChanged).update);

  /// Plays [media] on the receiver, replacing whatever it was playing —
  /// there is no queue.
  ///
  /// Accepted is not playing: follow [castUpdates] (or [castStatus]) to know
  /// whether the TV could open it.
  Future<CastReceipt> send(CastMedia media) async {
    final body = await _request('POST', '/v1/casts', body: media.toJson());
    final receipt = readResponse(() => CastReceipt.fromJson(body));
    _sent = (castId: receipt.castId, media: media);
    return receipt;
  }

  /// What this session sent as the cast [castId], if it was its last one.
  ///
  /// The API reports what plays without its poster, so this is how a remote
  /// control shows one. Null for a video another phone sent, or one sent
  /// before the app restarted.
  CastMedia? sentMedia(String castId) =>
      _sent?.castId == castId ? _sent?.media : null;

  /// Where the cast [castId] is on its way to the screen.
  Future<CastUpdate> castStatus(String castId) async {
    final body = await _request(
      'GET',
      '/v1/casts/${Uri.encodeComponent(castId)}',
    );
    return readResponse(() => CastUpdate.fromJson(body));
  }

  /// Asks the server what the receiver is playing. Not needed while
  /// [events] is listened to.
  Future<Playback?> fetchPlayback() async {
    final body = await _request('GET', '/v1/sessions/playback');
    final playback = readResponse(() => _readPlayback(body['playback']));
    _emit(PlaybackChanged(playback));
    return playback;
  }

  /// Sends [command] to the receiver's player and returns its id, which
  /// shows up as [Playback.lastCommandId] once the TV applied it.
  ///
  /// The TV applies it right away; one it cannot take within 10 s is
  /// dropped. Fails with `nothing_playing` when no video is loaded.
  Future<String> command(CastCommand command) async {
    final body = await _request(
      'POST',
      '/v1/sessions/commands',
      body: command.toJson(),
    );
    return readResponse(() => body.string('commandId'));
  }

  Future<String> play({String? castId}) =>
      command(CastCommand.play(castId: castId));

  Future<String> pause({String? castId}) =>
      command(CastCommand.pause(castId: castId));

  /// Closes the receiver's player. The session stays connected.
  Future<String> stop({String? castId}) =>
      command(CastCommand.stop(castId: castId));

  Future<String> seek(Duration position, {String? castId}) =>
      command(CastCommand.seek(position, castId: castId));

  /// Moves by [offset] from where the video is; negative goes back.
  Future<String> skip(Duration offset, {String? castId}) =>
      command(CastCommand.skip(offset, castId: castId));

  /// Sets the player's volume, 0–100.
  Future<String> setVolume(int level, {String? castId}) =>
      command(CastCommand.volume(level, castId: castId));

  Future<String> setMuted(bool muted, {String? castId}) =>
      command(CastCommand.mute(muted, castId: castId));

  /// Turns on the subtitle [trackId] (one of [Playback.subtitles]), or turns
  /// subtitles off with null.
  Future<String> setSubtitles(String? trackId, {String? castId}) =>
      command(CastCommand.subtitles(trackId, castId: castId));

  /// Switches to the audio [trackId] (one of [Playback.audioTracks]).
  Future<String> setAudio(String trackId, {String? castId}) =>
      command(CastCommand.audio(trackId, castId: castId));

  /// Ends the session and frees the receiver for another code. Safe to call
  /// on a session that is already over; a network failure is not reported,
  /// since the session expires on its own.
  Future<void> disconnect() async {
    if (isOver) return;
    _finish(CastEndReason.disconnected);
    try {
      await _transport.send('DELETE', '/v1/sessions', auth: _auth);
    } on CastException {
      // Nothing to undo: for this app the session is already closed.
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (_endReason case final reason?) {
      throw CastApiException(
        code: CastErrorCode.sessionEnded,
        statusCode: 410,
        message: 'The session is over (${reason.name})',
      );
    }
    try {
      return await _transport.sendForObject(
        method,
        path,
        auth: _auth,
        body: body,
      );
    } on CastApiException catch (error) {
      if (error.sessionOver) _finish(CastEndReason.unknown);
      rethrow;
    }
  }

  Playback? _readPlayback(Object? json) => json is Map<String, Object?>
      ? Playback.fromJson(json, receivedAt: _clock())
      : null;

  void _emit(CastEvent event) {
    if (event case PlaybackChanged(:final playback)) _playback = playback;
    if (!_events.isClosed && _events.hasListener) _events.add(event);
  }

  /// Marks the session as over, tells the listeners and stops everything.
  void _finish(CastEndReason reason) {
    if (isOver) return;
    _endReason = reason;
    _over.complete(reason);
    _emit(CastStreamEnded(reason));
    _stopFollowing();
    unawaited(_events.close());
  }

  // ── Following ────────────────────────────────────────────────────────────

  void _startFollowing() {
    if (isOver) return;
    unawaited(_follow(++_generation));
  }

  void _stopFollowing() {
    _generation++;
    unawaited(_stream?.cancel());
    _stream = null;
    _interrupt?.call();
    _interrupt = null;
  }

  bool _current(int generation) => generation == _generation && !isOver;

  /// Keeps the event stream open; whenever it cannot, polls for a while and
  /// tries again, doubling that while each time the stream gives nothing.
  Future<void> _follow(int generation) async {
    var window = _timings.pollInterval;
    while (_current(generation)) {
      final outcome = await _listenOnce(generation);
      if (!_current(generation)) return;

      switch (outcome) {
        case _StreamOutcome.dropped:
          window = _timings.pollInterval;
          await _wait(_timings.reconnectDelay);
        case _StreamOutcome.silent:
          await _pollFor(window, generation);
          window = window * 2 > _timings.maxRetryWindow
              ? _timings.maxRetryWindow
              : window * 2;
        case _StreamOutcome.superseded:
          // The server asked not to reopen it: this session has newer
          // streams elsewhere. Polling keeps the listeners up to date.
          await _pollFor(null, generation);
      }
    }
  }

  /// Opens the event stream and forwards it until it ends.
  Future<_StreamOutcome> _listenOnce(int generation) async {
    final Stream<List<int>> bytes;
    try {
      bytes = await _transport.openEventStream(
        '/v1/sessions/events',
        auth: _auth,
      );
    } on CastApiException catch (error) {
      if (error.sessionOver) _finish(CastEndReason.unknown);
      return _StreamOutcome.silent;
    } on CastNetworkException {
      return _StreamOutcome.silent;
    }

    final done = Completer<_StreamOutcome>();
    var heard = false;
    void finish(_StreamOutcome outcome) {
      if (!done.isCompleted) done.complete(outcome);
    }

    // Any byte counts as life, pings included, so the watch is kept on the
    // bytes and not on the messages read out of them.
    Timer? idle;
    void stillAlive() {
      idle?.cancel();
      idle = Timer(
        _timings.streamIdleTimeout,
        () => finish(_outcomeOfDrop(heard)),
      );
    }

    stillAlive();
    final subscription =
        parseSse(
          bytes.map((chunk) {
            stillAlive();
            return chunk;
          }),
        ).listen(
          (message) {
            heard = true;
            if (_handle(message) case final outcome?) finish(outcome);
          },
          onError: (Object _) => finish(_outcomeOfDrop(heard)),
          onDone: () => finish(_outcomeOfDrop(heard)),
          cancelOnError: true,
        );

    if (_current(generation)) {
      _stream = subscription;
      _interrupt = () => finish(_StreamOutcome.dropped);
    } else {
      // Following stopped while the request was in flight.
      finish(_StreamOutcome.dropped);
    }

    final outcome = await done.future;
    idle?.cancel();
    if (identical(_stream, subscription)) _stream = null;
    unawaited(subscription.cancel());
    return outcome;
  }

  static _StreamOutcome _outcomeOfDrop(bool heard) =>
      heard ? _StreamOutcome.dropped : _StreamOutcome.silent;

  /// Turns one message into its event. Returns how the stream ended when the
  /// message is the server's goodbye.
  _StreamOutcome? _handle(SseMessage message) {
    final Object? data;
    try {
      data = jsonDecode(message.data);
    } on FormatException {
      return null;
    }

    switch (message.event) {
      case 'playback':
        try {
          _emit(PlaybackChanged(_readPlayback(data)));
        } on FormatException {
          // A state without its cast says nothing; keep the last good one.
        }
      case 'cast' when data is Map<String, Object?>:
        try {
          _emit(CastStatusChanged(CastUpdate.fromJson(data)));
        } on FormatException {
          // A cast event without its id says nothing; skip it.
        }
      case 'ended':
        final reason = CastEndReason.of(
          data is Map<String, Object?> ? data.stringOrNull('reason') : null,
        );
        if (reason.sessionOver) {
          _finish(reason);
          return _StreamOutcome.dropped;
        }
        _emit(CastStreamEnded(reason));
        return _StreamOutcome.superseded;
    }
    return null;
  }

  /// Asks for playback every [CastTimings.pollInterval] during [window], or
  /// for as long as following lasts when it is null.
  Future<void> _pollFor(Duration? window, int generation) async {
    final rounds = window == null
        ? null
        : (window.inMicroseconds / _timings.pollInterval.inMicroseconds).ceil();
    for (var round = 0; rounds == null || round < rounds; round++) {
      try {
        await fetchPlayback();
      } on CastException {
        // Offline or throttled: the next round, or the stream, will tell.
      }
      if (!_current(generation)) return;
      await _wait(_timings.pollInterval);
      if (!_current(generation)) return;
    }
  }

  /// Waits [duration], or until following stops.
  Future<void> _wait(Duration duration) {
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    _interrupt = () {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    };
    return done.future;
  }
}

/// How one attempt at the event stream ended.
enum _StreamOutcome {
  /// It worked and then closed: reopen it.
  dropped,

  /// It could not be opened, or gave nothing before dying: poll meanwhile.
  silent,

  /// The server closed it for good, with the session still alive.
  superseded,
}
