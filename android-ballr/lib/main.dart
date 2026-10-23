import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const accent = Color(0xFFD1FB05);
const mint = Color(0xFF15FFB3);
const surface = Color(0xFF0C130C);
const background = Color(0xFF030603);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Receipts.record('STARTUP | BallR+ Android v1.0.1');
  runApp(const BallRApp());
}

class Receipts {
  static Future<File> _file() async {
    final folder = await getApplicationSupportDirectory();
    return File(folder.path + '/ballr-receipts.log');
  }

  static Future<void> record(String event) async {
    try {
      final file = await _file();
      final now = DateTime.now().toUtc().toIso8601String();
      await file.writeAsString(now + ' | ' + event + '\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging is best-effort. Never block opening the application.
    }
  }

  static Future<String> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return 'No receipts recorded.';
      final text = await file.readAsString();
      return text.length > 10000 ? text.substring(text.length - 10000) : text;
    } catch (error) {
      return 'LOG READ ERROR | ' + error.runtimeType.toString();
    }
  }
}

class BallRApp extends StatelessWidget {
  const BallRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BallR+',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent, secondary: mint, surface: surface),
        appBarTheme: const AppBarTheme(backgroundColor: background),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent, width: 2),
          ),
        ),
      ),
      home: const BallRHome(),
    );
  }
}

class BallRHome extends StatefulWidget {
  const BallRHome({super.key});

  @override
  State<BallRHome> createState() => _BallRHomeState();
}

class _BallRHomeState extends State<BallRHome> {
  String status = 'READY | Android companion';
  bool busy = false;

  void _status(String message) {
    if (mounted) setState(() { status = message; });
  }

  Future<void> _open(String target, String label) async {
    if (busy) return;
    setState(() { busy = true; });
    try {
      final uri = Uri.parse(target);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw StateError('No app can handle this link');
      await Receipts.record('OPEN SUCCESS | ' + label);
      _status('OPENED | ' + label);
    } catch (error) {
      await Receipts.record('OPEN FAILURE | ' + label + ' | ' +
          error.runtimeType.toString());
      _status('ERROR | Could not open ' + label);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open ' + label +
              '. Check internet access and installed applications.')));
      }
    } finally {
      if (mounted) setState(() { busy = false; });
    }
  }

  Future<void> _joinMeeting() async {
    final input = TextEditingController();
    final meeting = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String error = '';
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: surface,
            title: const Text('JOIN ZOOM MEETING'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Enter the numeric meeting ID. Zoom handles sign-in '
                  'and any meeting passcode.'),
              const SizedBox(height: 16),
              TextField(
                controller: input,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 16,
                decoration: InputDecoration(
                  labelText: 'Meeting ID',
                  hintText: 'Enter meeting number',
                  errorText: error.isEmpty ? null : error,
                ),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL')),
              FilledButton(onPressed: () {
                final id = input.text.replaceAll(RegExp(r'[^0-9]'), '');
                if (id.length < 9 || id.length > 11) {
                  setDialogState(() { error = 'Use a 9 to 11 digit meeting ID'; });
                  return;
                }
                Navigator.pop(ctx, id);
              }, child: const Text('JOIN')),
            ],
          );
        });
      },
    );
    input.dispose();
    if (meeting == null) return;
    await _open('https://zoom.us/j/' + meeting, 'Zoom meeting');
  }

  Future<void> _logs() async {
    final logs = await Receipts.read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('STARTUP RECEIPTS'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(
            logs, style: const TextStyle(fontSize: 12)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Future<void> _about() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('ABOUT BALLR+'),
        content: const Text(
          'BallR+ Android v1.0.1\n\n'
          'A mobile companion for BallRoom and Zoom. '
          'Open Zoom, join a meeting using an ID, browse the directory, '
          'and read diagnostic receipts.\n\n'
          'Windows-only temporary-account features are not supported on Android. '
          'There is no built-in activation or licensing check.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String title, String detail,
      VoidCallback callback) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: busy ? null : callback,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFF52693C))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2C0D),
                  borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: accent, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    color: accent, fontSize: 16,
                    fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(detail, style: const TextStyle(
                    color: Color(0xFFBBC8B4), fontSize: 12)),
                ],
              )),
              const Icon(Icons.chevron_right, color: accent),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 34),
            children: [
              Container(height: 6, decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0xFFFD0093), accent, mint]),
                borderRadius: BorderRadius.circular(8))),
              const SizedBox(height: 23),
              Row(children: [
                Container(
                  width: 59, height: 59,
                  decoration: const BoxDecoration(
                    color: accent, shape: BoxShape.circle),
                  child: const Center(child: Text('B+', style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w900,
                    fontSize: 25))),
                ),
                const SizedBox(width: 15),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('BallR+', style: TextStyle(
                      color: accent, fontWeight: FontWeight.w900,
                      fontSize: 34, letterSpacing: -1)),
                    Text('BY BALLROOM  |  1132.WTF', style: TextStyle(
                      fontSize: 11, letterSpacing: 1.2,
                      color: mint, fontWeight: FontWeight.bold)),
                  ],
                )),
              ]),
              const SizedBox(height: 24),
              Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101A0F),
                  borderRadius: BorderRadius.circular(15)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ZOOM COMPANION', style: TextStyle(
                      fontSize: 12, color: mint, letterSpacing: 1.8,
                      fontWeight: FontWeight.bold)),
                    SizedBox(height: 7),
                    Text('Your BallRoom access, in your pocket.',
                      style: TextStyle(fontSize: 17,
                        fontWeight: FontWeight.w600)),
                  ])),
              const SizedBox(height: 26),
              _action(Icons.video_call_outlined, 'OPEN ZOOM',
                'Launch Zoom or open its website',
                () => _open('https://zoom.us/', 'Zoom')),
              _action(Icons.meeting_room_outlined, 'JOIN A MEETING',
                'Join by meeting ID in Zoom',
                _joinMeeting),
              _action(Icons.list_alt_outlined, 'ROOM DIRECTORY',
                'Browse BallRoom meeting listings',
                () => _open('https://1132.wtf/pages/zoom-directory',
                    'Room directory')),
              _action(Icons.language, 'BALLROOM WEBSITE',
                'Open 1132.wtf',
                () => _open('https://1132.wtf', 'BallRoom website')),
              _action(Icons.volunteer_activism_outlined, 'SUPPORT BALLROOM',
                'Open the community support page',
                () => _open('https://linktr.ee/ballzoom', 'Support')),
              _action(Icons.receipt_long_outlined, 'STARTUP RECEIPTS',
                'See launch history and actionable failures', _logs),
              _action(Icons.info_outline, 'ABOUT THIS APP',
                'App version and Android feature limits', _about),
              const SizedBox(height: 7),
              if (busy) const LinearProgressIndicator(color: accent),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: const Color(0xFF3E5C24)),
                  borderRadius: BorderRadius.circular(10)),
                child: Text(status, maxLines: 2,
                  style: const TextStyle(color: accent, fontSize: 12,
                    fontWeight: FontWeight.w600))),
              const SizedBox(height: 22),
              const Center(child: Text('BALLR+  |  ANDROID EDITION',
                style: TextStyle(color: Color(0xFF8BA48E),
                  letterSpacing: 1.4, fontSize: 10))),
            ],
          ),
        ),
      )),
    );
  }
}
