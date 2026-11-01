import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';

// Windows app only.

/// Every tag with how many books have it: rename one (renaming it to a tag
/// that already exists merges the two) or delete it from all books.
class TagsScreen extends StatelessWidget {
  const TagsScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final BookRepository repository;
  final AppSettings settings;

  Future<void> _rename(BuildContext context, String tag) async {
    final controller = TextEditingController(text: tag);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Rename "$tag"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New name',
            helperText: 'Use the name of another tag to merge them',
          ),
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty || clean == tag) return;
    // Merging into a tag that exists keeps that tag's own spelling.
    final existing = repository.allTags.firstWhere(
      (t) => t != tag && t.toLowerCase() == clean.toLowerCase(),
      orElse: () => clean,
    );
    await repository.renameTag(tag, existing);
    settings.renameTagEverywhere(tag, existing);
  }

  Future<void> _delete(BuildContext context, String tag, int count) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete "$tag"?'),
        content: Text(
          'The tag is taken off $count ${count == 1 ? 'book' : 'books'}. '
          'The books themselves stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await repository.deleteTag(tag);
    settings.renameTagEverywhere(tag, null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final counts = repository.tagCounts;
          final tags = counts.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          if (tags.isEmpty) {
            return const Center(child: Text('No tags yet.'));
          }
          return ListView.builder(
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              final count = counts[tag]!;
              return ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(tag),
                subtitle: Text('$count ${count == 1 ? 'book' : 'books'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Rename or merge',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _rename(context, tag),
                    ),
                    IconButton(
                      tooltip: 'Delete from all books',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, tag, count),
                    ),
                  ],
                ),
                onTap: () => _rename(context, tag),
              );
            },
          );
        },
      ),
    );
  }
}
