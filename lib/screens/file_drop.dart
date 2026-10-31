import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../audio/audio_files.dart';
import '../audio/audio_library.dart';
import '../audio/listening.dart';
import '../data/backup.dart';
import '../data/book_repository.dart';
import '../data/cover_image.dart';
import '../data/csv.dart';
import '../data/dropped_file.dart';
import '../data/kindle_clippings.dart';
import '../ebook/ebook_library.dart';
import '../ebook/ebook_reading.dart';
import 'add_file_flow.dart';
import 'cover_actions.dart';

/// Drop a Chapterly backup, a CSV file or My Clippings.txt anywhere on the
/// window to import it. A picture becomes the cover of the book that is
/// open. An EPUB or PDF, or an audiobook (its file, its files or its
/// folder), is linked to its book in the library, as with Add file.
class FileDropTarget extends StatefulWidget {
  const FileDropTarget({
    super.key,
    required this.repository,
    required this.child,
    this.onLinked,
  });

  final BookRepository repository;
  final Widget child;

  /// Shows the book a dropped book file or audiobook was linked to.
  final void Function(String bookId)? onLinked;

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  bool _hovering = false;
  bool _busy = false;

  void _say(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _hovering = false);
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Book files and audiobooks are linked to books; the rest is
      // imported as before.
      final books = <PickedFile>[];
      final audio = <PickedFile>[];
      final folders = <String>[];
      final handled = <Object>{};
      for (final file in details.files) {
        if (await FileSystemEntity.isDirectory(file.path)) {
          folders.add(file.path);
        } else if (ebookFormatOf(file.name) != null) {
          books.add(PickedFile(location: file.path, name: file.name));
        } else if (isAudioFileName(file.name)) {
          audio.add(PickedFile(location: file.path, name: file.name));
        } else {
          continue;
        }
        handled.add(file);
      }
      final others =
          details.files.where((file) => !handled.contains(file)).toList();
      if ((books.isNotEmpty && EbookReading.library == null) ||
          ((audio.isNotEmpty || folders.isNotEmpty) &&
              Listening.controller == null)) {
        _say(messenger, 'Book files and audiobooks cannot be added here.');
      }
      void linked(String bookId) => widget.onLinked?.call(bookId);
      for (final book in books) {
        if (!mounted) return;
        await linkBookFile(
          context,
          repository: widget.repository,
          picked: book,
          onLinked: linked,
        );
      }
      if (audio.isNotEmpty) {
        if (!mounted) return;
        // Several files dropped together are one audiobook, named after
        // their folder.
        await linkAudiobook(
          context,
          repository: widget.repository,
          picked: audio,
          folder: audio.length > 1,
          onLinked: linked,
        );
      }
      for (final folder in folders) {
        if (!mounted) return;
        final files = await audioFilesIn(folder);
        if (!mounted) return;
        await linkAudiobook(
          context,
          repository: widget.repository,
          picked: files,
          folder: true,
          onLinked: linked,
        );
      }

      for (final file in others) {
        if (isCoverImageFile(file.name)) {
          final id = ShownBooks.current;
          if (id == null) {
            _say(
              messenger,
              'Open a book first, then drop the picture to make it the cover.',
            );
            continue;
          }
          await useCoverPicture(
            messenger,
            widget.repository,
            id,
            await file.readAsBytes(),
          );
          continue;
        }
        String text;
        try {
          text = stripBom(await file.readAsString());
        } catch (_) {
          _say(messenger, 'Could not read ${file.name}.');
          continue;
        }
        if (!mounted) return;
        await _import(messenger, file.name, text);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _import(
    ScaffoldMessengerState messenger,
    String name,
    String text,
  ) async {
    final repository = widget.repository;
    try {
      switch (detectDroppedFile(name, text)) {
        case DroppedFileKind.backup:
          final restored = decodeBackup(text);
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Restore backup?'),
              content: Text(
                'This replaces your ${repository.books.length} current books '
                'with the ${restored.length} books in $name.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Restore'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          await repository.replaceAll(restored);
          _say(messenger, 'Restored ${restored.length} books.');
        case DroppedFileKind.csv:
          final result = importBooksFromCsv(text);
          final added = await repository.importBooks(result.books);
          final duplicates = result.books.length - added;
          final parts = ['Imported $added book${added == 1 ? '' : 's'}'];
          if (duplicates > 0) parts.add('$duplicates already in your library');
          if (result.skipped > 0) parts.add('${result.skipped} skipped');
          _say(messenger, '${parts.join(', ')}.');
        case DroppedFileKind.kindle:
          final match = matchClippings(
            repository.books,
            parseKindleClippings(text),
          );
          await repository.addQuotesToBooks(match.quotesByBook);
          final bookCount = match.quotesByBook.length;
          final missing = match.unmatchedTitles.length;
          final quotes = match.added == 1 ? 'quote' : 'quotes';
          final books = bookCount == 1 ? 'book' : 'books';
          final unmatched = missing == 0
              ? ''
              : '. $missing ${missing == 1 ? 'title has' : 'titles have'} '
                  'no matching book in your library';
          _say(
            messenger,
            'Added ${match.added} $quotes to $bookCount $books$unmatched.',
          );
        case DroppedFileKind.unknown:
          _say(
            messenger,
            "Chapterly can't import $name. Drop a Chapterly backup (.json), "
            'a CSV file, My Clippings.txt, or a picture for a cover.',
          );
      }
    } on FormatException catch (error) {
      _say(messenger, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _dropped,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Drop an EPUB, PDF or audiobook to add it to its '
                        'book, a backup, a CSV file or My Clippings.txt to '
                        'import it, or a picture for the open book\'s cover',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
