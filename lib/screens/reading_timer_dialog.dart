import 'dart:async';

import 'package:flutter/material.dart';

/// A simple stopwatch. Returns the minutes read (at least 1, rounded up),
/// or null if cancelled or nothing was timed.
Future<int?> showReadingTimerDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ReadingTimerDialog(),
  );
}

class _ReadingTimerDialog extends StatefulWidget {
  const _ReadingTimerDialog();

  @override
  State<_ReadingTimerDialog> createState() => _ReadingTimerDialogState();
}

class _ReadingTimerDialogState extends State<_ReadingTimerDialog> {
  final _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _ticker?.cancel();
      } else {
        _stopwatch.start();
        _ticker = Timer.periodic(
          const Duration(seconds: 1),
          (_) => setState(() {}),
        );
      }
    });
  }

  String _clock() {
    final total = _stopwatch.elapsed.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  void _save() {
    final seconds = _stopwatch.elapsed.inSeconds;
    Navigator.of(context).pop(seconds <= 0 ? null : (seconds / 60).ceil());
  }

  @override
  Widget build(BuildContext context) {
    final started = _stopwatch.elapsed.inSeconds > 0;
    return AlertDialog(
      title: const Text('Reading timer'),
      content: Center(
        heightFactor: 1,
        child: Text(
          _clock(),
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _toggle,
          child: Text(_stopwatch.isRunning ? 'Pause' : 'Start'),
        ),
        FilledButton(
          onPressed: started ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
