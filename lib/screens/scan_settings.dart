import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/calibre.dart';
import '../data/library_scan.dart';
import '../models/shelf.dart';
import 'scan_progress.dart';
import 'scan_review_screen.dart';

// Windows app only.

/// Settings for linking your EPUB, PDF and audiobook folders to your books.
class ScanSettings extends StatelessWidget {
  const ScanSettings({
    super.key,
    required this.settings,
    required this.repository,
    required this.scanner,
  });

  final AppSettings settings;
  final BookRepository repository;
  final LibraryScanner scanner;

  Future<void> _pick(bool books) async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Use this folder',
    );
    if (folder == null) return;
    if (books) {
      settings.setBooksFolder(folder);
    } else {
      settings.setAudiobooksFolder(folder);
    }
  }

  Future<void> scanNow(BuildContext context) async {
    final result = await showScanProgress(
      context,
      scanner,
      'Scanning your folders',
      scanner.scan(
        booksFolder: settings.booksFolder,
        audiobooksFolder: settings.audiobooksFolder,
      ),
    );
    if (result == null) return;
    settings.setLastScan(DateTime.now());
    if (!context.mounted) return;
    final lines = <String>[
      if (result.looked == 0)
        'No new or changed files found.'
      else ...[
        if (result.linkedBooks > 0)
          'Linked ${result.linkedBooks} book '
              '${result.linkedBooks == 1 ? 'file' : 'files'}.',
        if (result.linkedAudiobooks > 0)
          'Linked ${result.linkedAudiobooks} '
              '${result.linkedAudiobooks == 1 ? 'audiobook' : 'audiobooks'}.',
        if (result.linked == 0) 'Nothing could be linked by itself.',
        if (result.review.isNotEmpty)
          '${result.review.length} '
              '${result.review.length == 1 ? 'file needs' : 'files need'} '
              'your decision.',
      ],
      ...result.problems,
    ];
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Scan finished'),
        content: Text(lines.join('\n')),
        actions: [
          if (result.review.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                _review(context);
              },
              child: const Text('Review'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> importCalibre(BuildContext context) async {
    final folder = settings.booksFolder;
    if (folder == null) return;
    final plan = await showScanProgress(
      context,
      scanner,
      'Reading the Calibre library',
      scanner.planCalibre(folder),
    );
    if (plan == null || !context.mounted) return;
    final add = plan.where((e) => e.outcome == CalibreOutcome.add).length;
    final fill = plan.where((e) => e.outcome == CalibreOutcome.fill).length;
    final unsure = plan.length - add - fill;
    if (plan.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('No Calibre books found'),
          content: const Text(
            'Chapterly found no metadata.opf files in the books folder. '
            'Choose your Calibre library folder (the one with metadata.db) '
            'as the books folder, and keep Calibre\'s "Save metadata in OPF" '
            'on.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    var shelf = Shelf.forLater;
    var linkFiles = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: const Text('Import from Calibre'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${plan.length} books in the Calibre library.\n'
                '• $add not in your library yet: they will be added\n'
                '• $fill already in your library: blank details and covers '
                'are filled in, nothing you wrote is changed\n'
                '• $unsure might be books you have: left alone',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Shelf>(
                initialValue: shelf,
                decoration: const InputDecoration(
                  labelText: 'Put added books on',
                ),
                items: [
                  for (final value in Shelf.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) =>
                    setState(() => shelf = value ?? Shelf.forLater),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Also link their book files'),
                value: linkFiles,
                onChanged: (value) => setState(() => linkFiles = value ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: add + fill == 0 ? null : () => Navigator.pop(dialog, true),
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    final result = await showScanProgress(
      context,
      scanner,
      'Importing from Calibre',
      scanner.importCalibre(plan, shelf: shelf, linkFiles: linkFiles),
    );
    if (result == null || !context.mounted) return;
    final lines = [
      'Added ${result.added} ${result.added == 1 ? 'book' : 'books'}.',
      if (result.linked > 0) 'Linked ${result.linked} files.',
      if (result.filled > 0)
        'Filled in details for ${result.filled} '
            '${result.filled == 1 ? 'book' : 'books'} you had.',
      ...result.problems,
    ];
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Import finished'),
        content: Text(lines.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _review(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ScanReviewScreen(
        scanner: scanner,
        repository: repository,
      ),
    ));
  }

  static String _when(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, scanner]),
      builder: (context, _) {
        final books = settings.booksFolder;
        final audio = settings.audiobooksFolder;
        final last = settings.lastScanAt;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Books folder'),
              subtitle: Text(books ?? 'Not set. Your EPUB and PDF files.'),
              trailing: books == null
                  ? null
                  : IconButton(
                      tooltip: 'Stop using this folder',
                      icon: const Icon(Icons.close),
                      onPressed: () => settings.setBooksFolder(null),
                    ),
              onTap: () => _pick(true),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Audiobooks folder'),
              subtitle: Text(audio ?? 'Not set. Your audiobook files.'),
              trailing: audio == null
                  ? null
                  : IconButton(
                      tooltip: 'Stop using this folder',
                      icon: const Icon(Icons.close),
                      onPressed: () => settings.setAudiobooksFolder(null),
                    ),
              onTap: () => _pick(false),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.autorenew),
              title: const Text('Scan when Chapterly opens'),
              subtitle: const Text(
                'Links new files that clearly match a book in your library. '
                'Nothing is replaced or added without asking.',
              ),
              value: settings.scanOnOpen,
              onChanged: settings.setScanOnOpen,
            ),
            ListTile(
              leading: scanner.running
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Icon(Icons.search),
              title: const Text('Scan now'),
              subtitle: Text(
                scanner.running
                    ? scanner.message
                    : !settings.hasScanFolders
                        ? 'Choose a folder first.'
                        : last == null
                            ? 'Not scanned yet.'
                            : 'Last scan ${_when(last)}.',
              ),
              enabled: settings.hasScanFolders && !scanner.running,
              onTap: () => scanNow(context),
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('Import from Calibre library'),
              subtitle: const Text(
                'Adds books from the books folder when it is a Calibre '
                'library, with their covers and details.',
              ),
              enabled: books != null && !scanner.running,
              onTap: () => importCalibre(context),
            ),
            if (scanner.pending.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.checklist),
                title: Text(
                  'Review ${scanner.pending.length} '
                  '${scanner.pending.length == 1 ? 'file' : 'files'}',
                ),
                subtitle: const Text('Files Chapterly was not sure about.'),
                onTap: () => _review(context),
              ),
          ],
        );
      },
    );
  }
}
