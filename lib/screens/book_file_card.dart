import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../ebook/ebook_files.dart';
import '../ebook/ebook_library.dart';
import '../ebook/ebook_reading.dart';
import '../ebook/reader_stats.dart';
import '../ebook/reader_style.dart';
import '../models/book.dart';
import 'reader_screen.dart';

/// The book's EPUB or PDF file on the book page: add one, read it, change
/// it or remove it. Hidden when the reader is not set up (tests).
class BookFileCard extends StatefulWidget {
  const BookFileCard({super.key, required this.book, required this.repository});

  final Book book;
  final BookRepository repository;

  @override
  State<BookFileCard> createState() => _BookFileCardState();
}

class _BookFileCardState extends State<BookFileCard> {
  bool _adding = false;

  Future<void> _add() async {
    final library = EbookReading.library;
    final files = EbookReading.files;
    final booksDir = EbookReading.booksDir;
    if (library == null || files == null || booksDir == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await () async {
      try {
        return await files.pickBook();
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the file picker.')),
        );
        return null;
      }
    }();
    if (picked == null || !mounted) return;
    setState(() => _adding = true);
    final problem = await addBookFile(
      library: library,
      files: files,
      booksDir: booksDir,
      bookId: widget.book.id,
      picked: picked,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    messenger.showSnackBar(
      SnackBar(content: Text(problem ?? 'Added "${picked.name}"')),
    );
  }

  Future<void> _remove() async {
    final library = EbookReading.library;
    if (library == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove the book file?'),
        content: const Text(
          'Chapterly deletes its copy of the file, with your bookmarks and '
          'highlights in it. The file you picked is not touched, and your '
          'quotes and current page stay on the book.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure == true) await removeBookFile(library, widget.book.id);
  }

  void _read() {
    final library = EbookReading.library;
    if (library == null) return;
    openReader(
      context,
      repository: widget.repository,
      library: library,
      bookId: widget.book.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = EbookReading.library;
    if (library == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final link = library.linkFor(widget.book.id);
        final position = link?.position;
        final stats = link == null || link.days.isEmpty
            ? null
            : readerStatsFor(link, bookPages: widget.book.pages);
        final pace = stats?.pagesPerHour;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chrome_reader_mode_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Book file', style: textTheme.titleMedium),
                    ),
                    if (link != null)
                      PopupMenuButton<VoidCallback>(
                        tooltip: 'More',
                        onSelected: (action) => action(),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _add,
                            child: const Text('Use another file...'),
                          ),
                          PopupMenuItem(
                            value: _remove,
                            child: const Text('Remove the book file'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (link == null) ...[
                  const Text(
                    'Read this book in Chapterly: add its EPUB or PDF file '
                    'from this device. Chapterly keeps its own copy, on this '
                    'device only.',
                  ),
                  const SizedBox(height: 8),
                  if (_adding)
                    const _Copying()
                  else
                    OutlinedButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Add the book file'),
                    ),
                ] else ...[
                  Text(link.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    '${link.format.label} · ${formatFileSize(link.bytes)} · '
                    'on this device',
                    style: textTheme.bodySmall,
                  ),
                  if (position != null && position.progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: position.progress,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            percentText(position.progress),
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (stats != null && stats.minutes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          '${formatMinutes(stats.minutes)} in the reader',
                          if (pace != null) pagesPerHourText(pace).toLowerCase(),
                        ].join(' · '),
                        style: textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_adding)
                    const _Copying()
                  else
                    FilledButton.icon(
                      onPressed: _read,
                      icon: const Icon(Icons.menu_book),
                      label: Text(
                        position != null && position.progress > 0
                            ? 'Continue reading'
                            : 'Start reading',
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Copying extends StatelessWidget {
  const _Copying();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Copying the file...'),
        ],
      ),
    );
  }
}
