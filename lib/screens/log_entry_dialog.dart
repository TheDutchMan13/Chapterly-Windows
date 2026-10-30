import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'reading_timer_dialog.dart';

/// Pages read and minutes spent reading, for the reading log.
typedef LogAmounts = ({int pages, int minutes});

/// Asks for pages and/or minutes. Returns null if cancelled or both are empty.
Future<LogAmounts?> showLogEntryDialog(BuildContext context) {
  return showDialog<LogAmounts>(
    context: context,
    builder: (_) => const _LogEntryDialog(),
  );
}

class _LogEntryDialog extends StatefulWidget {
  const _LogEntryDialog();

  @override
  State<_LogEntryDialog> createState() => _LogEntryDialogState();
}

class _LogEntryDialogState extends State<_LogEntryDialog> {
  final _pages = TextEditingController();
  final _minutes = TextEditingController();

  @override
  void dispose() {
    _pages.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _useTimer() async {
    final minutes = await showReadingTimerDialog(context);
    if (minutes == null || !mounted) return;
    setState(() => _minutes.text = minutes.toString());
  }

  void _save() {
    final pages = int.tryParse(_pages.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    Navigator.of(context).pop(
      pages <= 0 && minutes <= 0 ? null : (pages: pages, minutes: minutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to reading log'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pages,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Pages read'),
          ),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Minutes read'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _useTimer,
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Use a timer'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
