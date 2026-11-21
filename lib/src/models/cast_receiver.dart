import 'package:meta/meta.dart';
import 'package:playeroff_cast/src/models/json.dart';

/// The receiver a session is connected to.
@immutable
final class CastReceiver {
  const CastReceiver({required this.platform, this.name = ''});

  factory CastReceiver.fromJson(Map<String, Object?> json) => CastReceiver(
    platform: ReceiverPlatform.of(json.stringOrNull('platform')),
    name: json.stringOrNull('name') ?? '',
  );

  final ReceiverPlatform platform;

  /// The name the receiver gave itself; often empty.
  final String name;

  /// Whether this receiver sends a cast's `headers` with its requests. Only
  /// the Android TV app does; elsewhere a video that needs them will not
  /// load, which an app can tell the person before sending it.
  bool get appliesHeaders => platform == ReceiverPlatform.android;

  Map<String, Object?> toJson() => {'platform': platform.wire, 'name': name};

  @override
  String toString() => 'CastReceiver(${platform.name}, "$name")';
}

/// Where the receiver app runs.
enum ReceiverPlatform {
  /// Samsung.
  tizen,

  /// LG.
  webos,

  /// Android TV.
  android,

  /// Hisense.
  vidaa,

  /// A browser tab.
  web,

  /// A platform this version does not know.
  unknown;

  static ReceiverPlatform of(String? wire) =>
      values.asNameMap()[wire] ?? ReceiverPlatform.unknown;

  String get wire => name;
}
