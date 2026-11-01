import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/duplicates.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';

/// Books that look like the same book. Merge each group into one book.
class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key, required this.repository, this.settings});

  final BookRepository repository;

  /// Remembers pairs you said are not the same (Windows app).
  final AppSettings? settings;

  String _describe(Book book) => [
        book.title,
        if (book.author.isNotEmpty) book.author,
        book.shelf.label,
        if (book.format != null) book.format!.label,
        if (book.pages != null) '${book.pages} pages',
        if (book.isbn != null) 'ISBN ${book.isbn}',
      ].join(' · ');

  Future<void> _merge(BuildContext context, List<Book> group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Merge these books?'),
        content: const Text(
          'The one with the most details is kept. Missing details, tags, '
          'quotes and earlier readings are copied into it from the others. '
          'The other copies go to the trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final before = [...group];
    await repository.mergeDuplicates(group);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Merged. The extra copies are in the trash.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.putBack(before),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duplicates')),
      body: ListenableBuilder(
        listenable: Listenable.merge([repository, ?settings]),
        builder: (context, _) {
          final groups = repository.findDuplicates();
          final possible = findPossibleDuplicates(
            repository.books,
            dismissed: settings?.notDuplicates ?? const {},
          );
          if (groups.isEmpty && possible.isEmpty) {
            return const Center(child: Text('No duplicates found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'These books have the same ISBN, or the same title and '
                  'author. Different editions of one book (for example a '
                  'paperback and an audiobook) show up here too, so only '
                  'merge the ones that are really the same copy.',
                ),
              ),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('No exact duplicates.'),
                ),
              for (final group in groups)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final book in group)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(_describe(book)),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: () => _merge(context, group),
                            child: const Text('Merge'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (possible.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                  child: Text(
                    'Possible duplicates',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'These look alike but are not exactly the same: a typo, '
                    'a subtitle on one, or an edition name. Check them '
                    'before merging.',
                  ),
                ),
                for (final pair in possible)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pair.reason,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(_describe(pair.first)),
                          Text(_describe(pair.second)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                if (settings != null)
                                  TextButton(
                                    onPressed: () =>
                                        settings!.addNotDuplicate(pair.key),
                                    child: const Text('Not the same'),
                                  ),
                                FilledButton(
                                  onPressed: () => _merge(
                                    context,
                                    [pair.first, pair.second],
                                  ),
                                  child: const Text('Merge'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
