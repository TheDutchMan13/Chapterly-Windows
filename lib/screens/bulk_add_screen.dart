import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/bulk_add.dart';
import '../data/open_library_client.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';

/// Paste a list of ISBNs or titles (one per line), look them all up on Open
/// Library, check the matches, and add them in one go. Returns how many
/// books were added.
class BulkAddScreen extends StatefulWidget {
  const BulkAddScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.settings,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;

  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _text = TextEditingController();
  List<BulkItem>? _items;
  bool _looking = false;
  bool _adding = false;
  late Shelf _shelf = widget.settings.defaultShelf ?? Shelf.forLater;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final lines = parseBulkLines(_text.text);
    if (lines.isEmpty) return;
    final items = [for (final line in lines) BulkItem(line)];
    setState(() {
      _items = items;
      _looking = true;
    });
    await lookUpAll(
      items,
      lookUp: (line) => lookUpLine(widget.client, line),
      library: widget.repository.books,
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() => _looking = false);
  }

  Future<void> _retry(BulkItem item) async {
    final controller = TextEditingController(text: item.line);
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Look up again'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title, "Title by Author", or ISBN',
          ),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Look up'),
          ),
        ],
      ),
    );
    controller.dispose();
    final line = typed?.trim() ?? '';
    final items = _items;
    if (line.isEmpty || items == null || !mounted) return;
    final replacement = BulkItem(line);
    setState(() => items[items.indexOf(item)] = replacement);
    await lookUpAll(
      [replacement],
      lookUp: (line) => lookUpLine(widget.client, line),
      library: widget.repository.books,
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _add() async {
    final items = _items;
    if (items == null) return;
    final chosen = [for (final item in items) if (item.include) item];
    if (chosen.isEmpty) return;
    setState(() => _adding = true);
    for (final item in chosen) {
      final match = item.match;
      await widget.repository.add(
        title: item.title,
        author: item.author,
        shelf: _shelf,
        tags: widget.settings.defaultTags,
        format: widget.settings.defaultFormat,
        isbn: item.isbn ?? match?.isbn,
        coverUrl: match?.coverUrl,
        firstPublishYear: match?.firstPublishYear,
        pages: match?.pages,
      );
    }
    if (mounted) Navigator.of(context).pop(chosen.length);
  }

  String _statusText(BulkItem item) {
    final parts = <String>[
      if (item.author.isNotEmpty) item.author,
      switch (item.status) {
        BulkStatus.waiting => 'Looking up...',
        BulkStatus.found => 'From Open Library',
        BulkStatus.notFound => item.isbn == null
            ? 'No match: adds it as you typed it'
            : 'No match for this ISBN',
        BulkStatus.failed => 'Could not reach Open Library',
      },
      if (item.owned) 'Already in your library',
    ];
    return parts.join(' · ');
  }

  Widget _pasteStep() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste one book per line: an ISBN, a title, or "Title by Author". '
            'Chapterly looks each one up on Open Library, then you choose '
            'which to add.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: true,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '9780441013593\nThe Hobbit\nKlara and the Sun by '
                    'Kazuo Ishiguro',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: parseBulkLines(_text.text).isEmpty ? null : _lookUp,
              icon: const Icon(Icons.search),
              label: Text(
                'Look up ${parseBulkLines(_text.text).length} '
                '${parseBulkLines(_text.text).length == 1 ? 'book' : 'books'}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep(List<BulkItem> items) {
    final done = items.where((i) => i.status != BulkStatus.waiting).length;
    final chosen = items.where((i) => i.include).length;
    return Column(
      children: [
        if (_looking)
          LinearProgressIndicator(
            value: items.isEmpty ? null : done / items.length,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Add to'),
              const SizedBox(width: 12),
              DropdownButton<Shelf>(
                value: _shelf,
                onChanged: (shelf) {
                  if (shelf != null) setState(() => _shelf = shelf);
                },
                items: [
                  for (final shelf in Shelf.values)
                    DropdownMenuItem(value: shelf, child: Text(shelf.label)),
                ],
              ),
              const Spacer(),
              Text('$done of ${items.length} looked up'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return CheckboxListTile(
                value: item.include,
                onChanged: item.addable
                    ? (value) => setState(() => item.include = value ?? false)
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                secondary: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BookCover(coverUrl: item.match?.coverUrl),
                    IconButton(
                      tooltip: 'Look up again',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: item.status == BulkStatus.waiting
                          ? null
                          : () => _retry(item),
                    ),
                  ],
                ),
                title: Text(item.title),
                subtitle: Text(_statusText(item)),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              TextButton(
                onPressed: _adding
                    ? null
                    : () => setState(() {
                          _items = null;
                          _looking = false;
                        }),
                child: const Text('Back to the list'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: chosen == 0 || _looking || _adding ? null : _add,
                icon: const Icon(Icons.library_add),
                label: Text('Add $chosen ${chosen == 1 ? 'book' : 'books'}'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Add several books')),
      body: items == null ? _pasteStep() : _reviewStep(items),
    );
  }
}
