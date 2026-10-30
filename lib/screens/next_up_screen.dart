import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../models/wish_priority.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';

enum _RowAction { top, up, down, start }

/// Your For later books in the order you will read them. Change the order
/// from the menu on each book. Books you have not placed yet follow the ones
/// you have, with the highest priority first.
class NextUpScreen extends StatelessWidget {
  const NextUpScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;

  void _open(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: repository,
          settings: settings,
          fileIo: fileIo,
          bookId: book.id,
        ),
      ),
    );
  }

  Future<void> _moveTo(List<Book> books, int from, int to) {
    if (to < 0 || to >= books.length || to == from) return Future.value();
    final ids = [for (final book in books) book.id];
    final id = ids.removeAt(from);
    ids.insert(to, id);
    return repository.setQueueOrder(ids);
  }

  Future<void> _act(
    BuildContext context,
    List<Book> books,
    int index,
    _RowAction action,
  ) async {
    switch (action) {
      case _RowAction.top:
        await _moveTo(books, index, 0);
      case _RowAction.up:
        await _moveTo(books, index, index - 1);
      case _RowAction.down:
        await _moveTo(books, index, index + 1);
      case _RowAction.start:
        final messenger = ScaffoldMessenger.of(context);
        final book = books[index];
        await repository.moveTo(book.id, Shelf.inProgress);
        messenger.showSnackBar(
          SnackBar(content: Text('Started "${book.title}"')),
        );
    }
  }

  String _subtitle(Book book) => [
        if (book.author.isNotEmpty) book.author,
        if (book.priority case final priority?) '${priority.label} priority',
        if (book.pages case final pages?) '$pages pages',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Next up')),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final books = repository.nextUp;
          if (books.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing is waiting. Books on your For later shelf show up '
                  'here, in the order you will read them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final pages = books.fold<int>(0, (sum, b) => sum + (b.pages ?? 0));
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${books.length} book${books.length == 1 ? '' : 's'}'
                  '${pages > 0 ? ' · $pages pages' : ''}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (var i = 0; i < books.length; i++)
                ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      BookCover(coverUrl: books[i].coverUrl),
                    ],
                  ),
                  title: Text(books[i].title),
                  subtitle: Text(_subtitle(books[i])),
                  onTap: () => _open(context, books[i]),
                  trailing: PopupMenuButton<_RowAction>(
                    tooltip: 'Change the order',
                    onSelected: (action) => _act(context, books, i, action),
                    itemBuilder: (_) => [
                      if (i > 0)
                        const PopupMenuItem(
                          value: _RowAction.top,
                          child: Text('Move to the top'),
                        ),
                      if (i > 0)
                        const PopupMenuItem(
                          value: _RowAction.up,
                          child: Text('Move up'),
                        ),
                      if (i < books.length - 1)
                        const PopupMenuItem(
                          value: _RowAction.down,
                          child: Text('Move down'),
                        ),
                      const PopupMenuItem(
                        value: _RowAction.start,
                        child: Text('Start reading'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
