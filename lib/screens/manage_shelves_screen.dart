import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/collections.dart';

/// Create, rename and delete your own shelves.
class ManageShelvesScreen extends StatelessWidget {
  const ManageShelvesScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final BookRepository repository;
  final AppSettings settings;

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Shelf name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await _askName(context, title: 'New shelf');
    if (name == null) return;
    settings.addCollection(name);
  }

  Future<void> _rename(BuildContext context, String name) async {
    final next = await _askName(context, title: 'Rename shelf', initial: name);
    if (next == null || next.trim().isEmpty || next.trim() == name) return;
    settings.renameCollection(name, next);
    await repository.renameCollection(name, next);
  }

  Future<void> _delete(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'The books stay in your library. They are only taken off this shelf.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    settings.removeCollection(name);
    await repository.deleteCollection(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your shelves'),
        actions: [
          IconButton(
            tooltip: 'New shelf',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([repository, settings]),
        builder: (context, _) {
          final names = allCollectionNames(settings, repository);
          if (names.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You have no shelves of your own yet. Tap + to make one, '
                  'for example "Book club". Each shelf gets its own tab on the '
                  'library screen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final name in names)
                ListTile(
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: Text(name),
                  subtitle: Text(
                    '${repository.booksInCollection(name).length} books',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(context, name),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(context, name),
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
