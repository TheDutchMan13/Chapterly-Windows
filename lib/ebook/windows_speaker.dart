import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'reader_tools.dart';

/// The voice built into Windows, through PowerShell and System.Speech.
/// Nothing extra needs installing. One PowerShell stays open while reading
/// and is sent one piece of text per line; it answers "done" after each.
class WindowsSpeaker implements Speaker {
  WindowsSpeaker();

  Process? _process;
  StreamSubscription<String>? _output;
  Completer<void>? _speaking;
  int _rate = 0;

  /// Set when PowerShell closed by itself (no voice, no sound device).
  bool _died = false;

  /// PowerShell's speed goes from -10 to 10; 1 is normal speed here.
  static int rateFor(double rate) {
    if (rate.isNaN) return 0;
    // About 0.5× at -10 and 2× at 10, 1× at 0.
    final value = rate >= 1 ? (rate - 1) * 10 : (rate - 1) * 20;
    return value.round().clamp(-10, 10);
  }

  static const _script = r'''
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.SetOutputToDefaultAudioDevice()
[Console]::Out.WriteLine('ready')
[Console]::Out.Flush()
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($line -eq $null) { break }
  if ($line.StartsWith('rate ')) {
    $voice.Rate = [int]$line.Substring(5)
    continue
  }
  if ($line.StartsWith('say ')) {
    try { $voice.Speak($line.Substring(4)) } catch { }
    [Console]::Out.WriteLine('done')
    [Console]::Out.Flush()
  }
}
''';

  Future<Process> _start() async {
    final running = _process;
    if (running != null) return running;
    // Sent as base64 UTF-16, PowerShell's way of taking a script safely.
    final units = _script.codeUnits;
    final bytes = <int>[for (final u in units) ...[u & 0xff, u >> 8]];
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64.encode(bytes),
    ]);
    process.stdin.encoding = utf8;
    final ready = Completer<void>();
    _output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final text = line.trim();
      if (text == 'ready' && !ready.isCompleted) ready.complete();
      if (text == 'done') _finish();
    });
    process.stderr.drain<void>();
    unawaited(process.exitCode.then((_) {
      if (identical(_process, process)) {
        _process = null;
        _died = true;
      }
      if (!ready.isCompleted) ready.complete();
      _finish();
    }));
    _process = process;
    await ready.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    process.stdin.writeln('rate $_rate');
    return process;
  }

  void _finish() {
    final speaking = _speaking;
    _speaking = null;
    if (speaking != null && !speaking.isCompleted) speaking.complete();
  }

  @override
  Future<void> speak(String text) async {
    final line = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (line.isEmpty) return;
    final process = await _start();
    final done = _speaking = Completer<void>();
    process.stdin.writeln('say $line');
    await done.future;
    if (_died) {
      _died = false;
      throw StateError('The Windows voice closed.');
    }
  }

  /// Stopping in the middle of a sentence means closing the voice; the next
  /// piece opens it again.
  @override
  Future<void> stop() async {
    final process = _process;
    _process = null;
    await _output?.cancel();
    _output = null;
    process?.kill();
    _finish();
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rateFor(rate);
    _process?.stdin.writeln('rate $_rate');
  }

  @override
  Future<void> dispose() => stop();
}
