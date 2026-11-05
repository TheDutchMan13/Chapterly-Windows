import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/book_source.dart';
import '../data/date_format.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import 'book_edit_screen.dart';

// The same file is in the Android app; keep the two copies alike.

/// Shows where a book came from: its original name (the file it was added
/// from), the details it was matched with, and a way to correct them. A
/// sheet from the bottom on a phone, a dialog on a wide window.
Future<void> showBookInfo(
  BuildContext context, {
  required BookRepository repository,
  required String bookId,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final edit = wide
      ? await showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: BookInfo(repository: repository, bookId: bookId),
              ),
            ),
          ),
        )
      : await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: BookInfo(repository: repository, bookId: bookId),
            ),
          ),
        );
  if (edit == true && context.mounted) {
    await openBookEditor(context, repository: repository, bookId: bookId);
  }
}

/// What [showBookInfo] shows. Pops true for "Edit this book".
class BookInfo extends StatefulWidget {
  const BookInfo({super.key, required this.repository, required this.bookId});

  final BookRepository repository;
  final String bookId;

  @override
  State<BookInfo> createState() => _BookInfoState();
}

class _BookInfoState extends State<BookInfo> {
  /// The name the server has for the file, asked once.
  late final Future<String?> _fromServer = serverFileName(widget.bookId);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final book = widget.repository.byId(widget.bookId);
        if (book == null) return const SizedBox.shrink();
        return FutureBuilder<String?>(
          future: _fromServer,
          builder: (context, snapshot) => _content(
            context,
            book,
            fromServer: snapshot.data,
            asking: snapshot.connectionState != ConnectionState.done,
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    Book book, {
    String? fromServer,
    required bool asking,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final origin = book.origin;
    final serverLinked = serverIdFor(book.id) != null;
    // The name kept with the book wins; then the server's; then the file
    // linked on this device.
    final name = origin?.name ?? fromServer ?? linkedFileName(book.id);
    final String explain;
    if (name != null) {
      explain = origin?.name != null
          ? _fromWhere(origin?.source)
          : fromServer != null
              ? 'The file name on your book server.'
              : 'The name of the file linked to this book.';
    } else if (asking && serverLinked) {
      explain = 'Asking your book server...';
    } else if (origin != null) {
      explain = 'This book was not added from a file. It was added as '
          '"${origin.title}".';
    } else {
      explain = 'Not recorded: this book was added before Chapterly kept '
          'original names, and no file is linked to it.';
    }
    final matchedDiffers = origin != null &&
        (origin.title != book.title || origin.author != book.author);
    final source = origin?.source ?? (serverLinked ? 'Your book server' : null);
    final edited = origin?.editedAt;
    final rows = <(String, String)>[
      if (origin != null && matchedDiffers)
        (
          'Matched as',
          [origin.title, if (origin.author.isNotEmpty) origin.author]
              .join(' · '),
        ),
      if (source != null) ('Added from', source),
      ('Added on', formatDate(book.addedAt)),
      if (edited != null) ('Edited by you', formatDate(edited)),
      if (book.isbn case final isbn? when isbn.isNotEmpty) ('ISBN', isbn),
      if (book.format case final format?) ('Format', format.label),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'SHOWN AS',
          style: text.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          book.title,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (book.author.isNotEmpty)
          Text(
            book.author,
            style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ORIGINAL NAME',
                style: text.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              if (name != null)
                SelectableText(
                  name,
                  style: text.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (asking && serverLinked)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 4),
              Text(
                explain,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  child: Text(
                    label,
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit this book'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    );
  }

  static String _fromWhere(String? source) => switch (source) {
        'Your book server' => 'The file name on your book server.',
        'A folder on this PC' => 'The name of the file (or audiobook folder) '
            'it was found as on this PC.',
        'A file you added' => 'The name of the file you added it from.',
        'A list of books you pasted' => 'The line you pasted to add it.',
        _ => 'The name it came with.',
      };
}
