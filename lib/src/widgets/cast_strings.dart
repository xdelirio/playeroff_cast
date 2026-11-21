import 'package:flutter/widgets.dart';
import 'package:playeroff_cast/playeroff_cast.dart';

/// The texts of the package's widgets, in English and Spanish.
///
/// Picked from the app's locale: Spanish for `es`, English for the rest.
@immutable
class CastStrings {
  const CastStrings.en()
    : connectTitle = 'Connect to PlayerOFF',
      connectHint =
          'Open PlayerOFF on the TV and type the code it shows on screen.',
      codeLabel = 'Code',
      connect = 'Connect',
      scanQr = 'Scan the QR',
      disconnect = 'Disconnect',
      castingToPattern = 'Casting to {tv}',
      connectedToPattern = 'Connected to {tv}',
      untitled = 'Untitled',
      nothingPlaying = 'Nothing is playing',
      play = 'Play',
      pause = 'Pause',
      stop = 'Stop',
      rewind = 'Back 10 seconds',
      forward = 'Forward 10 seconds',
      mute = 'Mute',
      unmute = 'Unmute',
      volume = 'Volume',
      subtitles = 'Subtitles',
      audio = 'Audio',
      off = 'Off',
      live = 'LIVE',
      stateLoading = 'Loading…',
      stateBuffering = 'Buffering…',
      stateEnded = 'Finished',
      stateStopped = 'Stopped',
      stateFailed = 'The TV could not play it',
      failedNetwork = 'The TV could not reach the video',
      failedUnsupported = 'The TV cannot play this format',
      failedDrm = 'The TV could not get the licence for this video',
      failedLocalNetwork = 'The TV could not open a local-network address',
      errorInvalidCode = 'That code is not valid or has expired',
      errorRateLimited = 'Too many attempts. Wait a few seconds',
      errorSessionEnded = 'The connection with the TV ended',
      errorNothingPlaying = 'Nothing is playing on the TV',
      errorCastMismatch = 'The TV is already playing another video',
      errorNetwork = 'No connection. Check your internet',
      errorGeneric = 'Something went wrong. Try again',
      tvSamsung = 'Samsung TV',
      tvLg = 'LG TV',
      tvAndroid = 'Android TV',
      tvHisense = 'Hisense TV',
      tvBrowser = 'Browser',
      tvGeneric = 'TV';

  const CastStrings.es()
    : connectTitle = 'Conectar con PlayerOFF',
      connectHint =
          'Abre PlayerOFF en el TV y escribe el código que muestra en pantalla.',
      codeLabel = 'Código',
      connect = 'Conectar',
      scanQr = 'Escanear el QR',
      disconnect = 'Desconectar',
      castingToPattern = 'Transmitiendo a {tv}',
      connectedToPattern = 'Conectado a {tv}',
      untitled = 'Sin título',
      nothingPlaying = 'No se está reproduciendo nada',
      play = 'Reproducir',
      pause = 'Pausar',
      stop = 'Detener',
      rewind = 'Retroceder 10 segundos',
      forward = 'Avanzar 10 segundos',
      mute = 'Silenciar',
      unmute = 'Activar sonido',
      volume = 'Volumen',
      subtitles = 'Subtítulos',
      audio = 'Audio',
      off = 'Desactivados',
      live = 'EN VIVO',
      stateLoading = 'Cargando…',
      stateBuffering = 'Cargando…',
      stateEnded = 'Terminado',
      stateStopped = 'Detenido',
      stateFailed = 'El TV no pudo reproducirlo',
      failedNetwork = 'El TV no pudo acceder al video',
      failedUnsupported = 'El TV no puede reproducir este formato',
      failedDrm = 'El TV no pudo obtener la licencia de este video',
      failedLocalNetwork = 'El TV no pudo abrir una dirección de la red local',
      errorInvalidCode = 'Ese código no es válido o ya caducó',
      errorRateLimited = 'Demasiados intentos. Espera unos segundos',
      errorSessionEnded = 'La conexión con el TV terminó',
      errorNothingPlaying = 'No hay nada reproduciéndose en el TV',
      errorCastMismatch = 'El TV ya está reproduciendo otro video',
      errorNetwork = 'Sin conexión. Revisa tu internet',
      errorGeneric = 'Algo salió mal. Inténtalo de nuevo',
      tvSamsung = 'TV Samsung',
      tvLg = 'TV LG',
      tvAndroid = 'Android TV',
      tvHisense = 'TV Hisense',
      tvBrowser = 'Navegador',
      tvGeneric = 'TV';

  /// The texts for the locale [context] is in.
  factory CastStrings.of(BuildContext context) =>
      CastStrings.forLocale(Localizations.maybeLocaleOf(context));

  factory CastStrings.forLocale(Locale? locale) => locale?.languageCode == 'es'
      ? const CastStrings.es()
      : const CastStrings.en();

  final String connectTitle;
  final String connectHint;
  final String codeLabel;
  final String connect;
  final String scanQr;
  final String disconnect;

  /// `{tv}` stands for the receiver's name.
  final String castingToPattern;
  final String connectedToPattern;
  final String untitled;
  final String nothingPlaying;
  final String play;
  final String pause;
  final String stop;
  final String rewind;
  final String forward;
  final String mute;
  final String unmute;
  final String volume;
  final String subtitles;
  final String audio;
  final String off;
  final String live;
  final String stateLoading;
  final String stateBuffering;
  final String stateEnded;
  final String stateStopped;
  final String stateFailed;
  final String failedNetwork;
  final String failedUnsupported;
  final String failedDrm;
  final String failedLocalNetwork;
  final String errorInvalidCode;
  final String errorRateLimited;
  final String errorSessionEnded;
  final String errorNothingPlaying;
  final String errorCastMismatch;
  final String errorNetwork;
  final String errorGeneric;
  final String tvSamsung;
  final String tvLg;
  final String tvAndroid;
  final String tvHisense;
  final String tvBrowser;
  final String tvGeneric;

  /// The header of a remote: which TV, and whether it is playing ours.
  String connection(CastReceiver receiver, {required bool casting}) =>
      (casting ? castingToPattern : connectedToPattern).replaceAll(
        '{tv}',
        receiverName(receiver),
      );

  /// What to tell the person when a call failed with [error].
  String error(Object error) => switch (error) {
    CastNetworkException() => errorNetwork,
    CastApiException(:final code) => switch (code) {
      CastErrorCode.invalidCode => errorInvalidCode,
      CastErrorCode.rateLimited => errorRateLimited,
      CastErrorCode.unauthorized ||
      CastErrorCode.sessionEnded => errorSessionEnded,
      CastErrorCode.nothingPlaying => errorNothingPlaying,
      CastErrorCode.castMismatch => errorCastMismatch,
      CastErrorCode.validationError ||
      CastErrorCode.notFound ||
      CastErrorCode.payloadTooLarge ||
      CastErrorCode.internal ||
      CastErrorCode.unknown => errorGeneric,
    },
    _ => errorGeneric,
  };

  /// What to show for a player that is not simply playing or paused; null
  /// when the state needs no words.
  String? status(Playback playback) => switch (playback.state) {
    PlaybackState.loading => stateLoading,
    PlaybackState.buffering => stateBuffering,
    PlaybackState.ended => stateEnded,
    PlaybackState.stopped => stateStopped,
    PlaybackState.failed => switch (playback.error) {
      'network' => failedNetwork,
      'unsupported' => failedUnsupported,
      'drm' => failedDrm,
      'local-network' || 'mixed-content' => failedLocalNetwork,
      _ => stateFailed,
    },
    PlaybackState.playing ||
    PlaybackState.paused ||
    PlaybackState.unknown => null,
  };

  /// The receiver's own name, or its kind when it has none.
  String receiverName(CastReceiver receiver) => receiver.name.trim().isNotEmpty
      ? receiver.name.trim()
      : switch (receiver.platform) {
          ReceiverPlatform.tizen => tvSamsung,
          ReceiverPlatform.webos => tvLg,
          ReceiverPlatform.android => tvAndroid,
          ReceiverPlatform.vidaa => tvHisense,
          ReceiverPlatform.web => tvBrowser,
          ReceiverPlatform.unknown => tvGeneric,
        };

  /// A track's label, falling back on its language.
  String trackName(CastTrack track) => track.label.trim().isNotEmpty
      ? track.label.trim()
      : track.lang.isNotEmpty
      ? track.lang.toUpperCase()
      : track.id;
}

/// `1:02:03` or `2:03`.
String formatCastDuration(Duration duration) {
  final total = duration.isNegative ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
