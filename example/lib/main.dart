import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:playeroff_cast/playeroff_cast.dart';
import 'package:playeroff_cast/widgets.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'playeroff_cast',
    // The package's widgets draw with whatever theme is around them.
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    // …and speak Spanish or English with the app's locale.
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('es')],
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _cast = PlayeroffCast();
  final _url = TextEditingController(
    text: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  );
  CastSession? _session;

  @override
  void dispose() {
    _session?.disconnect();
    _cast.close();
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final session = await showCastConnectSheet(context, cast: _cast);
    if (session != null && mounted) setState(() => _session = session);
  }

  Future<void> _send(CastSession session) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = CastStrings.of(context);
    try {
      await session.send(
        CastMedia(
          url: Uri.parse(_url.text.trim()),
          title: 'Example video',
          // Shown on the TV while it loads, and by the remote and mini bar.
          poster: Uri.parse('https://picsum.photos/seed/playeroff/1280/720'),
        ),
      );
    } on CastException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(strings.error(error))));
    }
  }

  void _forget(CastEndReason reason) {
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return Scaffold(
      appBar: AppBar(title: const Text('playeroff_cast')),
      body: session == null
          ? Center(
              child: FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.cast),
                label: Text(CastStrings.of(context).connectTitle),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'Video URL'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => _send(session),
                  child: const Text('Send to the TV'),
                ),
                const Divider(height: 48),
                CastRemote(session: session, onEnded: _forget),
              ],
            ),
      bottomNavigationBar: session == null
          ? null
          : SafeArea(child: CastMiniBar(session: session)),
    );
  }
}
