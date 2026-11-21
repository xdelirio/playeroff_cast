import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:playeroff_cast/playeroff_cast.dart';
import 'package:playeroff_cast/src/widgets/cast_strings.dart';
import 'package:playeroff_cast/src/widgets/playeroff_logo.dart';

/// Shows [CastConnectForm] in a bottom sheet and returns the session it
/// opened, or null when the person left without connecting.
///
/// [initialCode] is a code the app already has — from a `playeroff://` deep
/// link, say — and is connected with right away. [onScanQr] is the app's QR
/// scanner; without it the form only takes a typed code.
Future<CastSession?> showCastConnectSheet(
  BuildContext context, {
  required PlayeroffCast cast,
  String? initialCode,
  Future<String?> Function()? onScanQr,
}) => showModalBottomSheet<CastSession>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: CastConnectForm(
        cast: cast,
        initialCode: initialCode,
        onScanQr: onScanQr,
        onConnected: (session) => Navigator.of(context).pop(session),
      ),
    ),
  ),
);

/// Asks for the code a TV shows and connects to it.
///
/// Draws with the theme around it. Meant for a sheet or a dialog — see
/// [showCastConnectSheet] — but it is a plain column and fits a page too.
class CastConnectForm extends StatefulWidget {
  const CastConnectForm({
    required this.cast,
    required this.onConnected,
    this.initialCode,
    this.onScanQr,
    super.key,
  });

  final PlayeroffCast cast;

  /// Called with the session once the code was accepted.
  final ValueChanged<CastSession> onConnected;

  /// A code to start with; when it is whole the form connects by itself.
  final String? initialCode;

  /// Opens the app's QR scanner and returns what it read (the QR's content
  /// as is, or just the code), or null when the person backed out. The
  /// scanner is the app's because cameras, permissions and scanning
  /// libraries are — this package has none. The QR is light on dark: some
  /// scanners need inverted reading turned on.
  final Future<String?> Function()? onScanQr;

  @override
  State<CastConnectForm> createState() => _CastConnectFormState();
}

class _CastConnectFormState extends State<CastConnectForm> {
  late final TextEditingController _code;
  bool _connecting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(
      text: CastCode.parse(widget.initialCode ?? '') ?? '',
    );
    if (CastCode.isComplete(_code.text)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting || !mounted) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final session = await widget.cast.connect(_code.text);
      if (!mounted) {
        // Nobody is left to use it: free the TV for the next code.
        await session.disconnect();
        return;
      }
      setState(() => _connecting = false);
      widget.onConnected(session);
    } on CastException catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error;
      });
    }
  }

  Future<void> _scan() async {
    final scanned = await widget.onScanQr!();
    if (!mounted || scanned == null) return;
    final code = CastCode.parse(scanned);
    if (code == null) {
      setState(
        () => _error = const CastApiException(
          code: CastErrorCode.invalidCode,
          statusCode: 404,
          message: 'The QR holds no PlayerOFF code',
        ),
      );
      return;
    }
    _code.text = code;
    await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final strings = CastStrings.of(context);
    final theme = Theme.of(context);
    final error = _error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The mark the person is looking at on the TV: it says, before any
        // word is read, which app the code comes from.
        const Center(child: PlayeroffLogo(size: 48)),
        const SizedBox(height: 12),
        Text(
          strings.connectTitle,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          strings.connectHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: _code,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _code,
                enabled: !_connecting,
                autofocus: _code.text.isEmpty,
                autocorrect: false,
                enableSuggestions: false,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.visiblePassword,
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 8,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                inputFormatters: const [_CodeFormatter()],
                decoration: InputDecoration(
                  labelText: strings.codeLabel,
                  floatingLabelAlignment: FloatingLabelAlignment.center,
                  errorText: error == null ? null : strings.error(error),
                  errorMaxLines: 2,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) {
                  if (CastCode.isComplete(_code.text)) _connect();
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _connecting || !CastCode.isComplete(_code.text)
                    ? null
                    : _connect,
                child: _connecting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(strings.connect),
              ),
            ],
          ),
        ),
        if (widget.onScanQr != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _connecting ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(strings.scanQr),
          ),
        ],
      ],
    );
  }
}

/// Keeps the field to what a code can hold: its alphabet, upper-cased, and
/// its length. Pasting `k7m-3qx` leaves `K7M3QX`.
class _CodeFormatter extends TextInputFormatter {
  const _CodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final kept = newValue.text
        .toUpperCase()
        .split('')
        .where(CastCode.alphabet.contains)
        .take(CastCode.length)
        .join();
    return kept == newValue.text
        ? newValue
        : TextEditingValue(
            text: kept,
            selection: TextSelection.collapsed(offset: kept.length),
          );
  }
}
