import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/match_review.dart';
import '../data/open_library_client.dart';
import '../widgets/book_cover.dart';
import 'book_edit_screen.dart';

// The same file is in the Android app; keep the two copies alike.

/// Books whose details look very different from their original name (the
/// file they came from), so a wrong Open Library match is easy to find and
/// fix. "It's right" stops a book being listed again.
class ReviewMatchesScreen extends StatelessWidget {
  const ReviewMatchesScreen({
    super.key,
    required this.repository,
    this.client,
  });

  final BookRepository repository;
  final OpenLibraryClient? client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review matches')),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final books = repository.books;
          final doubtful = doubtfulMatches(books);
          final fine = fineMatchCount(books);
          final textTheme = Theme.of(context).textTheme;
          final colours = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  doubtful.isEmpty
                      ? 'Every book with an original name looks like its '
                          'file. $fine ${fine == 1 ? 'book' : 'books'} checked.'
                      : '${doubtful.length} ${doubtful.length == 1 ? 'book looks' : 'books look'} '
                          'like ${doubtful.length == 1 ? 'it' : 'they'} may have '
                          'been matched to the wrong book: the details are very '
                          'different from the original name. $fine look fine.',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: colours.onSurfaceVariant),
                ),
              ),
              for (final item in doubtful)
                _DoubtfulCard(
                  key: ValueKey(item.book.id),
                  item: item,
                  onFind: () => openBookEditor(
                    context,
                    repository: repository,
                    bookId: item.book.id,
                    client: client,
                  ),
                  onRight: () => repository.confirmMatch(item.book.id),
                ),
              if (books.every((b) => b.origin?.name == null))
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Only books added with a file (from your book server, a '
                    'folder or a file you chose) have an original name to '
                    'compare with.',
                    style: textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DoubtfulCard extends StatelessWidget {
  const _DoubtfulCard({
    super.key,
    required this.item,
    required this.onFind,
    required this.onRight,
  });

  final DoubtfulMatch item;
  final VoidCallback onFind;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    final book = item.book;
    final textTheme = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final muted = textTheme.labelMedium?.copyWith(color: colours.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(
                  coverUrl: book.coverUrl,
                  width: 48,
                  height: 72,
                  title: book.title,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Matched as', style: muted),
                      Text(
                        [book.title, if (book.author.isNotEmpty) book.author]
                            .join(' · '),
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text('Original name', style: muted),
                      Text(
                        book.origin?.name ?? '',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colours.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'How alike the details and the original name are',
                  child: Chip(
                    label: Text('${item.percent} alike'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onFind,
                    child: const Text('Find match'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onRight,
                  child: const Text("It's right"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
