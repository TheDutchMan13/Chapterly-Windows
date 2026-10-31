import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/library_scan.dart';
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

  Future<void> _scan(BuildContext context) async {
    final result = await scanner.scan(
      booksFolder: settings.booksFolder,
      audiobooksFolder: settings.audiobooksFolder,
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
              onTap: () => _scan(context),
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
