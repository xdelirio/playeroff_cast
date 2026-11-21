import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:playeroff_cast/src/cast_exception.dart';
import 'package:playeroff_cast/src/models/json.dart';

/// How a request proves who it is.
sealed class CastAuth {
  const CastAuth();

  Map<String, String> get headers;
}

/// A phone's session (`Authorization: Bearer`).
final class SessionAuth extends CastAuth {
  const SessionAuth(this.token);

  final String token;

  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $token'};
}

/// A receiver's secret (`X-Receiver-Secret`). Never goes in a URL.
final class ReceiverAuth extends CastAuth {
  const ReceiverAuth(this.secret);

  final String secret;

  @override
  Map<String, String> get headers => {'X-Receiver-Secret': secret};
}

/// The HTTP side of the API: JSON in, JSON out, and every failure turned
/// into a [CastException].
final class CastTransport {
  CastTransport({
    required this.baseUrl,
    required http.Client client,
    required this.requestTimeout,
  }) : _client = client;

  final Uri baseUrl;
  final Duration requestTimeout;
  final http.Client _client;

  /// Sends one request and returns its decoded body, or null when the
  /// response has none (204).
  Future<Object?> send(
    String method,
    String path, {
    CastAuth? auth,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _resolve(path, query))
      ..headers.addAll({'Accept': 'application/json', ...?auth?.headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
    } on Object catch (error) {
      throw _network(error);
    }

    if (response.statusCode >= 400) throw _apiError(response);
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw CastNetworkException('Unreadable response', cause: error);
    }
  }

  /// Like [send], for the endpoints that answer with a JSON object.
  Future<Map<String, Object?>> sendForObject(
    String method,
    String path, {
    CastAuth? auth,
    Map<String, Object?>? body,
  }) async {
    final decoded = await send(method, path, auth: auth, body: body);
    if (decoded is Map<String, Object?>) return decoded;
    throw const CastNetworkException('Unexpected response');
  }

  /// Opens a `text/event-stream` and returns its bytes. The connection stays
  /// open until the subscription to them is cancelled.
  Future<Stream<List<int>>> openEventStream(
    String path, {
    CastAuth? auth,
    Map<String, String>? query,
  }) async {
    final request = http.Request('GET', _resolve(path, query))
      ..headers.addAll({
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...?auth?.headers,
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(requestTimeout);
    } on Object catch (error) {
      throw _network(error);
    }
    if (response.statusCode >= 400) {
      throw _apiError(await http.Response.fromStream(response));
    }
    return response.stream;
  }

  Uri _resolve(String path, Map<String, String>? query) {
    final base = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$base$path', queryParameters: query);
  }

  static CastNetworkException _network(Object error) => switch (error) {
    TimeoutException() => CastNetworkException('Timed out', cause: error),
    _ => CastNetworkException('Could not reach the server', cause: error),
  };

  static CastApiException _apiError(http.Response response) {
    Map<String, Object?>? error;
    try {
      if (jsonDecode(utf8.decode(response.bodyBytes))
          case final Map<String, Object?> body) {
        error = body.objectOrNull('error');
      }
    } on FormatException {
      // Not the API's own error: a proxy or a gateway answered.
    }
    final rawCode = error?.stringOrNull('code');
    return CastApiException(
      code: CastErrorCode.of(rawCode, response.statusCode),
      statusCode: response.statusCode,
      message: error?.stringOrNull('message') ?? 'HTTP ${response.statusCode}',
      rawCode: rawCode,
    );
  }
}
