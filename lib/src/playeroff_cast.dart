import 'package:http/http.dart' as http;
import 'package:playeroff_cast/src/cast_code.dart';
import 'package:playeroff_cast/src/cast_exception.dart';
import 'package:playeroff_cast/src/cast_session.dart';
import 'package:playeroff_cast/src/cast_timings.dart';
import 'package:playeroff_cast/src/models/cast_receiver.dart';
import 'package:playeroff_cast/src/models/json.dart';
import 'package:playeroff_cast/src/transport/cast_transport.dart';

/// The way into PlayerOFF for an app that sends videos: turns the code on a
/// TV into a [CastSession].
///
/// The API is open — no sign-up, no key — and keeps nothing: codes, casts
/// that were not delivered and sessions are all temporary.
final class PlayeroffCast {
  /// [baseUrl] is the server the receivers register with; a code only works
  /// on the server that issued it. [client] is the app's own HTTP client,
  /// when it has one to share (it is then the app's to close).
  PlayeroffCast({
    Uri? baseUrl,
    http.Client? client,
    this.timings = const CastTimings(),
    DateTime Function() clock = DateTime.now,
  }) : baseUrl = baseUrl ?? defaultBaseUrl,
       _ownsClient = client == null,
       _client = client ?? http.Client(),
       _clock = clock {
    _transport = CastTransport(
      baseUrl: this.baseUrl,
      client: _client,
      requestTimeout: timings.requestTimeout,
    );
  }

  /// The public server. The API's guide writes its examples against
  /// `beta.playeroff.app`; the one receivers register with is this.
  static final defaultBaseUrl = Uri.parse('https://playeroff.app');

  final Uri baseUrl;
  final CastTimings timings;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  late final CastTransport _transport;

  /// Connects to the receiver showing [code].
  ///
  /// [code] is what the person typed or what the QR holds
  /// (`playeroff://connect?code=…`); see [CastCode.parse]. A code works
  /// once, and connecting ends the session of whoever was connected before.
  ///
  /// Fails with [CastErrorCode.invalidCode] when the code does not exist,
  /// was used or expired (they last 5 minutes; the TV shows a new one), and
  /// with [CastErrorCode.rateLimited] after too many attempts.
  Future<CastSession> connect(String code) async {
    final normalized = CastCode.parse(code);
    if (normalized == null) {
      throw const CastApiException(
        code: CastErrorCode.invalidCode,
        statusCode: 404,
        message: 'Not a PlayerOFF code',
      );
    }
    final body = await _transport.sendForObject(
      'POST',
      '/v1/sessions',
      body: {'code': normalized},
    );
    return _session(
      token: readResponse(() => body.string('sessionToken')),
      receiver: CastReceiver.fromJson(body.objectOrNull('receiver') ?? {}),
      expiresAt: body.epochOrNull('expiresAt'),
    );
  }

  /// Takes up a session again from the [token] an earlier [connect] gave,
  /// after an app restart.
  ///
  /// Nothing is asked of the server here: if the session ended meanwhile,
  /// the first call (or the event stream) says so. [receiver] is whatever
  /// the app kept of the original one.
  CastSession resume(
    String token, {
    CastReceiver receiver = const CastReceiver(
      platform: ReceiverPlatform.unknown,
    ),
  }) => _session(token: token, receiver: receiver);

  /// Releases the HTTP client, unless the app supplied it. Sessions stop
  /// working afterwards.
  void close() {
    if (_ownsClient) _client.close();
  }

  CastSession _session({
    required String token,
    required CastReceiver receiver,
    DateTime? expiresAt,
  }) => CastSession(
    transport: _transport,
    token: token,
    receiver: receiver,
    expiresAt: expiresAt,
    timings: timings,
    clock: _clock,
  );
}
