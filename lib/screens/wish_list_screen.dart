import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/wish_list.dart';
import '../models/shelf.dart';
import '../models/wish_priority.dart';

// The same screen is in the Windows app.

/// Books you want but do not have yet. Search them, add them, and move one
/// into your library (For later) when you get it.
class WishListScreen extends StatefulWidget {
  const WishListScreen({
    super.key,
    required this.repository,
    required this.settings,
  });

  final BookRepository repository;
  final AppSettings settings;

  @override
  State<WishListScreen> createState() => _WishListScreenState();
}

class _WishListScreenState extends State<WishListScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _newId() => 'w${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _edit(Wish? existing) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final author = TextEditingController(text: existing?.author ?? '');
    final isbn = TextEditingController(text: existing?.isbn ?? '');
    final where = TextEditingController(text: existing?.where ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    var priority = existing?.priority;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialog) => AlertDialog(
          title: Text(existing == null ? 'Add to wish list' : 'Edit wish'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: existing == null,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: author,
                  decoration: const InputDecoration(labelText: 'Author'),
                ),
                TextField(
                  controller: isbn,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'ISBN (optional)'),
                ),
                DropdownButtonFormField<WishPriority?>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Not set')),
                    for (final p in WishPriority.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (value) => setDialog(() => priority = value),
                ),
                TextField(
                  controller: where,
                  decoration: const InputDecoration(
                    labelText: 'Where to get it',
                    helperText: 'A shop, a library or a link',
                  ),
                ),
                TextField(
                  controller: note,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final cleanTitle = title.text.trim();
    if (saved == true && cleanTitle.isNotEmpty) {
      final wish = Wish(
        id: existing?.id ?? _newId(),
        title: cleanTitle,
        author: author.text.trim(),
        isbn: isbn.text.trim().isEmpty ? null : isbn.text.trim(),
        priority: priority,
        where: where.text.trim().isEmpty ? null : where.text.trim(),
        note: note.text.trim(),
        addedAt: existing?.addedAt ?? DateTime.now(),
      );
      widget.settings.setWishes([
        for (final w in widget.settings.wishes)
          if (w.id == wish.id) wish else w,
        if (existing == null) wish,
      ]);
    }
  }

  /// Puts the wish in the library on For later, with its priority and where
  /// to get it, and takes it off the wish list.
  Future<void> _moveToLibrary(Wish wish) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.add(
      title: wish.title,
      author: wish.author,
      shelf: Shelf.forLater,
      isbn: wish.isbn,
    );
    final id = widget.repository.books.first.id;
    if (wish.priority != null) {
      await widget.repository.setPriority(id, wish.priority);
    }
    if (wish.where != null) {
      await widget.repository.setBuyAt(id, wish.where);
    }
    widget.settings.setWishes([
      for (final w in widget.settings.wishes)
        if (w.id != wish.id) w,
    ]);
    messenger.showSnackBar(
      SnackBar(content: Text('"${wish.title}" is in your library')),
    );
  }

  void _delete(Wish wish) {
    widget.settings.setWishes([
      for (final w in widget.settings.wishes)
        if (w.id != wish.id) w,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wish list')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final all = widget.settings.wishes;
          final shown = searchWishes(all, _query.text);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search your wish list',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _query.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nothing here yet. Add books you want to buy or '
                            'borrow. When you get one, move it to your library.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : shown.isEmpty
                        ? const Center(child: Text('No wishes match.'))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: shown.length,
                            itemBuilder: (context, index) {
                              final wish = shown[index];
                              final details = [
                                if (wish.author.isNotEmpty) wish.author,
                                if (wish.priority != null)
                                  wish.priority!.label,
                                if (wish.where != null) wish.where!,
                              ].join(' · ');
                              return ListTile(
                                leading: const Icon(Icons.favorite_outline),
                                title: Text(wish.title),
                                subtitle:
                                    details.isEmpty ? null : Text(details),
                                onTap: () => _edit(wish),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Move to my library',
                                      icon: const Icon(
                                          Icons.library_add_outlined),
                                      onPressed: () => _moveToLibrary(wish),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(wish),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}
