import 'package:flutter/material.dart';

import '../data/library_scan.dart';

// Windows app only.

/// Shows a window with a progress bar and the file being worked on while
/// [work] (a scan or an import started on [scanner]) runs, and closes it
/// when the work is done. The window can be hidden; the work carries on.
Future<T> showScanProgress<T>(
  BuildContext context,
  LibraryScanner scanner,
  String title,
  Future<T> work,
) async {
  final navigator = Navigator.of(context);
  var shown = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: scanner,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: scanner.progress),
              const SizedBox(height: 12),
              Text(scanner.message.isEmpty ? 'Working...' : scanner.message),
              if (scanner.current.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    scanner.current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'You can hide this window. The work carries on.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Hide'),
        ),
      ],
    ),
  ).whenComplete(() => shown = false);
  try {
    return await work;
  } finally {
    if (shown) navigator.pop();
  }
}
