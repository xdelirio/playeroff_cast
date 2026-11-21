import 'package:flutter/widgets.dart';

/// PlayerOFF's mark, shown where the app asks for the TV's code: the person
/// sees the same logo that is on the TV's screen.
///
/// It is the brand's own artwork, in its own colours, so it does not follow
/// the theme; [size] is its height.
class PlayeroffLogo extends StatelessWidget {
  const PlayeroffLogo({this.size = 24, this.semanticLabel, super.key});

  final double size;

  /// What a screen reader says; null when the widget around it already does.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/playeroff.png',
    package: 'playeroff_cast',
    height: size,
    // The mark is a little taller than wide: the height is what lines up
    // with the icons beside it.
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    semanticLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
  );
}
