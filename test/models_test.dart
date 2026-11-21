import 'package:flutter_test/flutter_test.dart';
import 'package:playeroff_cast/playeroff_cast.dart';

import 'support/fake_server.dart';

void main() {
  group('CastMedia.toJson', () {
    test('sends only the url when nothing else was given', () {
      final media = CastMedia(url: Uri.parse('https://example.com/a.m3u8'));
      expect(media.toJson(), {'url': 'https://example.com/a.m3u8'});
    });

    test('sends every field in the shape the API documents', () {
      final media = CastMedia(
        url: Uri.parse('https://example.com/a.mpd'),
        title: 'Film',
        poster: Uri.parse('https://example.com/p.jpg'),
        subtitles: [
          CastSubtitle(
            url: Uri.parse('https://example.com/es.vtt'),
            lang: 'es',
            label: 'Español',
          ),
          CastSubtitle(
            url: Uri.parse('https://example.com/en.vtt'),
            lang: 'en',
          ),
        ],
        startPosition: const Duration(seconds: 90, milliseconds: 500),
        storyboard: Uri.parse('https://example.com/thumbs.vtt'),
        headers: const {'Referer': 'https://example.com/'},
        drm: CastDrm(
          system: DrmSystem.widevine,
          licenseUrl: Uri.parse('https://licences.example.com'),
        ),
      );

      expect(media.toJson(), {
        'url': 'https://example.com/a.mpd',
        'title': 'Film',
        'poster': 'https://example.com/p.jpg',
        'subtitles': [
          {
            'url': 'https://example.com/es.vtt',
            'lang': 'es',
            'label': 'Español',
          },
          {'url': 'https://example.com/en.vtt', 'lang': 'en'},
        ],
        'startPosition': 90.5,
        'storyboard': {'url': 'https://example.com/thumbs.vtt'},
        'headers': {'Referer': 'https://example.com/'},
        'drm': {
          'system': 'widevine',
          'licenseUrl': 'https://licences.example.com',
        },
      });
    });
  });

  group('CastCommand.toJson', () {
    test('each command carries its own argument', () {
      const second = Duration(seconds: 1);
      expect(const CastCommand.play().toJson(), {'type': 'play'});
      expect(const CastCommand.pause().toJson(), {'type': 'pause'});
      expect(const CastCommand.stop().toJson(), {'type': 'stop'});
      expect(CastCommand.seek(second * 90).toJson(), {
        'type': 'seek',
        'position': 90.0,
      });
      expect(CastCommand.skip(second * -15).toJson(), {
        'type': 'skip',
        'seconds': -15.0,
      });
      expect(const CastCommand.volume(40).toJson(), {
        'type': 'volume',
        'level': 40,
      });
      expect(const CastCommand.mute(true).toJson(), {
        'type': 'mute',
        'muted': true,
      });
      expect(const CastCommand.audio('es').toJson(), {
        'type': 'audio',
        'trackId': 'es',
      });
    });

    test('turning subtitles off sends an explicit null', () {
      final json = const CastCommand.subtitles(null).toJson();
      expect(json, {'type': 'subtitles', 'trackId': null});
      expect(json.containsKey('trackId'), isTrue);
    });

    test('names the cast it is meant for when given one', () {
      expect(const CastCommand.pause(castId: 'cast-1').toJson(), {
        'type': 'pause',
        'castId': 'cast-1',
      });
    });
  });

  group('Playback', () {
    final received = DateTime.utc(2026, 11, 21, 12);

    Playback read(Map<String, Object?> json) =>
        Playback.fromJson(json, receivedAt: received);

    test('reads the state the API sends', () {
      final playback = read(playbackJson(position: 754.2, duration: 6120));

      expect(playback.castId, 'cast-1');
      expect(playback.title, 'Film');
      expect(playback.state, PlaybackState.playing);
      expect(playback.position, const Duration(milliseconds: 754200));
      expect(playback.duration, const Duration(seconds: 6120));
      expect(playback.volume, 80);
      expect(playback.muted, isFalse);
      expect(playback.subtitles, [
        const CastTrack(id: '54', lang: 'es', label: 'Español'),
      ]);
      expect(playback.activeSubtitle, isNull);
      expect(playback.activeAudio?.id, 'en');
      expect(
        playback.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1800000123000, isUtc: true),
      );
    });

    test('a live video has no duration', () {
      final playback = read(playbackJson(duration: null));
      expect(playback.duration, isNull);
      expect(playback.isLive, isTrue);
    });

    test('a state from a newer server reads as unknown', () {
      expect(
        read(playbackJson(state: 'rewinding')).state,
        PlaybackState.unknown,
      );
    });

    test('the position moves on by itself while playing', () {
      final playback = read(playbackJson(position: 10, duration: 100));
      expect(
        playback.positionAt(received.add(const Duration(seconds: 4))),
        const Duration(seconds: 14),
      );
    });

    test('the estimate never passes the end', () {
      final playback = read(playbackJson(position: 98, duration: 100));
      expect(
        playback.positionAt(received.add(const Duration(seconds: 30))),
        const Duration(seconds: 100),
      );
    });

    test('the position stays put when not playing', () {
      final later = received.add(const Duration(seconds: 30));
      for (final state in ['paused', 'buffering', 'loading', 'ended']) {
        expect(
          read(playbackJson(state: state)).positionAt(later),
          const Duration(seconds: 10),
          reason: state,
        );
      }
    });

    test('a clock that went backwards does not rewind the video', () {
      final playback = read(playbackJson());
      expect(
        playback.positionAt(received.subtract(const Duration(seconds: 5))),
        const Duration(seconds: 10),
      );
    });
  });

  group('status enums', () {
    test('know which casts are over', () {
      expect(CastStatus.playing.isFinal, isFalse);
      expect(CastStatus.pending.isFinal, isFalse);
      for (final status in ['ended', 'stopped', 'failed', 'expired']) {
        expect(CastStatus.of(status).isFinal, isTrue, reason: status);
      }
      expect(CastStatus.of('teleported'), CastStatus.unknown);
    });

    test('only a superseded stream leaves the session alive', () {
      expect(CastEndReason.superseded.sessionOver, isFalse);
      for (final reason in ['replaced', 'disconnected', 'expired', 'other']) {
        expect(CastEndReason.of(reason).sessionOver, isTrue, reason: reason);
      }
    });

    test('only the Android TV receiver applies headers', () {
      expect(
        const CastReceiver(platform: ReceiverPlatform.android).appliesHeaders,
        isTrue,
      );
      expect(
        const CastReceiver(platform: ReceiverPlatform.tizen).appliesHeaders,
        isFalse,
      );
    });
  });
}
