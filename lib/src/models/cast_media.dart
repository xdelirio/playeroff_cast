import 'package:meta/meta.dart';

/// A video to play on the receiver (`POST /v1/casts`).
///
/// The server never opens these URLs, it only forwards them, so addresses of
/// the local network (`http://192.168.x.x`, `*.local`) are fine. Limits —
/// 4096 characters per URL, 32 KB for the whole body — are enforced by the
/// server and come back as a `validation_error`.
@immutable
final class CastMedia {
  const CastMedia({
    required this.url,
    this.title,
    this.poster,
    this.subtitles = const [],
    this.startPosition,
    this.storyboard,
    this.headers = const {},
    this.drm,
  });

  /// HLS (`.m3u8`), DASH (`.mpd`), MP4 or WebM, over `http` or `https` and
  /// without credentials in the URL.
  final Uri url;

  /// Shown large in the receiver's player. Up to 200 characters.
  final String? title;

  /// An image shown while the video loads.
  final Uri? poster;

  /// External subtitles, at most 20. The first one is turned on by itself.
  final List<CastSubtitle> subtitles;

  /// Where to start, to resume what was being watched on the phone.
  final Duration? startPosition;

  /// A WebVTT of thumbnails for the receiver's seek bar; its cues point to
  /// images, usually sprites with `#xywh=x,y,width,height`. The web receiver
  /// does not show it yet.
  final Uri? storyboard;

  /// HTTP headers the receiver sends when it asks for the video, the
  /// subtitles and the storyboard (`Referer`, `User-Agent`, `Cookie`…).
  ///
  /// Only the Android TV receiver applies them; the others ignore them, so a
  /// video that needs headers does not play there — see
  /// `CastReceiver.appliesHeaders`. At most 20; connection headers (`Host`,
  /// `Content-Length`…) are rejected. They are never sent to the DRM licence
  /// server nor returned by the API.
  final Map<String, String> headers;

  final CastDrm? drm;

  Map<String, Object?> toJson() => {
    'url': url.toString(),
    'title': ?title,
    'poster': ?poster?.toString(),
    if (subtitles.isNotEmpty)
      'subtitles': [for (final subtitle in subtitles) subtitle.toJson()],
    if (startPosition case final position?)
      'startPosition': position.inMilliseconds / 1000,
    if (storyboard case final storyboard?)
      'storyboard': {'url': storyboard.toString()},
    if (headers.isNotEmpty) 'headers': headers,
    'drm': ?drm?.toJson(),
  };
}

/// An external subtitle file: WebVTT, SRT or TTML.
@immutable
final class CastSubtitle {
  const CastSubtitle({required this.url, required this.lang, this.label});

  final Uri url;

  /// A language tag (`es`, `pt-BR`), 2 to 16 characters.
  final String lang;

  /// What the receiver's menu shows. Up to 60 characters.
  final String? label;

  Map<String, Object?> toJson() => {
    'url': url.toString(),
    'lang': lang,
    'label': ?label,
  };
}

/// The licence server of a protected video.
@immutable
final class CastDrm {
  const CastDrm({required this.system, required this.licenseUrl});

  final DrmSystem system;

  /// Must be a public `https` address.
  final Uri licenseUrl;

  Map<String, Object?> toJson() => {
    'system': system.name,
    'licenseUrl': licenseUrl.toString(),
  };
}

enum DrmSystem { widevine, playready }
