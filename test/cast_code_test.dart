import 'package:flutter_test/flutter_test.dart';
import 'package:playeroff_cast/playeroff_cast.dart';

void main() {
  group('CastCode.parse', () {
    test('reads a typed code whatever its case and separators', () {
      expect(CastCode.parse('K7M3QX'), 'K7M3QX');
      expect(CastCode.parse(' k7m 3qx '), 'K7M3QX');
      expect(CastCode.parse('k7m-3qx'), 'K7M3QX');
    });

    test('reads the code out of the QR', () {
      expect(CastCode.parse('playeroff://connect?code=K7M3QX'), 'K7M3QX');
      expect(CastCode.parse('PLAYEROFF://connect?code=k7m3qx'), 'K7M3QX');
    });

    test('finds no code in a playeroff link that is not a connection', () {
      expect(CastCode.parse('playeroff://connect'), isNull);
      expect(CastCode.parse('playeroff://?data=abc'), isNull);
      expect(CastCode.parse('playeroff://open?code=K7M3QX'), isNull);
    });

    test('finds no code in text that cannot be one', () {
      expect(CastCode.parse(''), isNull);
      expect(CastCode.parse('   '), isNull);
      expect(CastCode.parse('https://example.com/?code=K7M3QX'), isNull);
      expect(CastCode.parse('¡hola!'), isNull);
    });

    test('leaves the length to the server', () {
      expect(CastCode.parse('K7M3QXAB'), 'K7M3QXAB');
    });
  });

  group('CastCode.fromUri', () {
    test('takes the QR link and nothing else', () {
      expect(
        CastCode.fromUri(Uri.parse('playeroff://connect?code=k7m3qx')),
        'K7M3QX',
      );
      expect(
        CastCode.fromUri(Uri.parse('https://connect?code=K7M3QX')),
        isNull,
      );
    });
  });

  group('CastCode.isComplete', () {
    test('is true for six characters of the alphabet', () {
      expect(CastCode.isComplete('K7M3QX'), isTrue);
      expect(CastCode.isComplete('k7m 3qx'), isTrue);
    });

    test('is false while typing, or with a character codes never use', () {
      expect(CastCode.isComplete('K7M3Q'), isFalse);
      expect(CastCode.isComplete('K7M3QXA'), isFalse);
      expect(CastCode.isComplete('K7M3Q0'), isFalse);
      expect(CastCode.isComplete('K7M3QI'), isFalse);
    });
  });
}
