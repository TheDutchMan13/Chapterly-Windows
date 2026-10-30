import 'package:flutter/material.dart';

import 'mini_timer.dart';

/// A simple stopwatch. Returns the minutes read (at least 1, rounded up),
/// or null if cancelled or nothing was timed. "Small window" shrinks
/// Chapterly to a little timer that stays on top while you read.
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
  final _watch = ReadingStopwatch();

  @override
  void dispose() {
    _watch.dispose();
    super.dispose();
  }

  void _save() {
    final seconds = _watch.elapsed.inSeconds;
    Navigator.of(context).pop(seconds <= 0 ? null : (seconds / 60).ceil());
  }

  void _small() {
    if (!_watch.isRunning) _watch.toggle();
    MiniTimer.instance.enter(_watch);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _watch,
      builder: (context, _) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Reading timer')),
            IconButton(
              tooltip: 'Small window that stays on top',
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              onPressed: _small,
            ),
          ],
        ),
        content: Center(
          heightFactor: 1,
          child: Text(
            _watch.clock,
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _watch.toggle,
            child: Text(_watch.isRunning ? 'Pause' : 'Start'),
          ),
          FilledButton(
            onPressed: _watch.started ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
