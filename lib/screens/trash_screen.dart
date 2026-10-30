import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../widgets/book_cover.dart';

/// Deleted books. Restore them, or delete them for good.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key, required this.repository});

  final BookRepository repository;

  Future<void> _confirmEmpty(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty trash?'),
        content: const Text('All books in the trash will be deleted for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.emptyTrash();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final books = repository.trash;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Trash'),
            actions: [
              if (books.isNotEmpty)
                IconButton(
                  tooltip: 'Empty trash',
                  icon: const Icon(Icons.delete_forever),
                  onPressed: () => _confirmEmpty(context),
                ),
            ],
          ),
          body: books.isEmpty
              ? const Center(child: Text('The trash is empty.'))
              : ListView.builder(
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final book = books[index];
                    final deleted = book.deletedAt;
                    return ListTile(
                      leading: BookCover(
                        coverUrl: book.coverUrl,
                      ),
                      title: Text(book.title),
                      subtitle: Text(
                        [
                          if (book.author.isNotEmpty) book.author,
                          if (deleted != null)
                            'Deleted ${formatDate(deleted)}',
                        ].join('\n'),
                      ),
                      isThreeLine: book.author.isNotEmpty && deleted != null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore),
                            onPressed: () => repository.restore(book.id),
                          ),
                          IconButton(
                            tooltip: 'Delete for good',
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () => repository.deleteForever(book.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
