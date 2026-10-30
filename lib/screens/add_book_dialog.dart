import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_repository.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';

class NewBookData {
  const NewBookData({
    required this.title,
    required this.author,
    required this.shelf,
    required this.tags,
    this.isbn,
    this.pages,
    this.format,
  });

  final String title;
  final String author;
  final Shelf shelf;
  final List<String> tags;
  final String? isbn;
  final int? pages;
  final BookFormat? format;
}

/// Returns the entered details, or null if the dialog was cancelled.
/// Pass [isbn] (for example from a scan) to save it with the book.
///
/// [initialShelf], [initialFormat] and [initialTags] fill in the form first
/// (the defaults from Settings).
Future<NewBookData?> showAddBookDialog(
  BuildContext context, {
  String? isbn,
  Shelf initialShelf = Shelf.forLater,
  BookFormat? initialFormat,
  List<String> initialTags = const [],
}) {
  return showDialog<NewBookData>(
    context: context,
    builder: (_) => _AddBookDialog(
      isbn: isbn,
      initialShelf: initialShelf,
      initialFormat: initialFormat,
      initialTags: initialTags,
    ),
  );
}

class _AddBookDialog extends StatefulWidget {
  const _AddBookDialog({
    this.isbn,
    required this.initialShelf,
    required this.initialFormat,
    required this.initialTags,
  });

  final String? isbn;
  final Shelf initialShelf;
  final BookFormat? initialFormat;
  final List<String> initialTags;

  @override
  State<_AddBookDialog> createState() => _AddBookDialogState();
}

class _AddBookDialogState extends State<_AddBookDialog> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _pages = TextEditingController();
  final _tags = TextEditingController();
  late Shelf _shelf = widget.initialShelf;
  late BookFormat? _format = widget.initialFormat;

  @override
  void initState() {
    super.initState();
    _tags.text = widget.initialTags.join(', ');
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _pages.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final pages = int.tryParse(_pages.text.trim());
    Navigator.of(context).pop(
      NewBookData(
        title: title,
        author: _author.text.trim(),
        shelf: _shelf,
        tags: parseTags(_tags.text),
        isbn: widget.isbn,
        pages: pages != null && pages > 0 ? pages : null,
        format: _format,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isbn = widget.isbn;
    return AlertDialog(
      title: const Text('Add book'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isbn != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('ISBN $isbn'),
              ),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _author,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            TextField(
              controller: _pages,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Pages (optional)'),
            ),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags',
                helperText: 'Separate with commas',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Shelf>(
              initialValue: _shelf,
              decoration: const InputDecoration(labelText: 'Shelf'),
              items: [
                for (final shelf in Shelf.values)
                  DropdownMenuItem(value: shelf, child: Text(shelf.label)),
              ],
              onChanged: (value) => setState(() => _shelf = value ?? _shelf),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BookFormat?>(
              initialValue: _format,
              decoration: const InputDecoration(labelText: 'Format'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not set')),
                for (final format in BookFormat.values)
                  DropdownMenuItem(value: format, child: Text(format.label)),
              ],
              onChanged: (value) => setState(() => _format = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
