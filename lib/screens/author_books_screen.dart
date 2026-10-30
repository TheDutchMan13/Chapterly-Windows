import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/open_library_client.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'shelf_picker.dart';

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Other books by an author, from Open Library, leaving out the ones you
/// already have. Tap one to add it to a shelf.
class AuthorBooksScreen extends StatefulWidget {
  const AuthorBooksScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.author,
    required this.settings,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final String author;
  final AppSettings settings;

  @override
  State<AuthorBooksScreen> createState() => _AuthorBooksScreenState();
}

class _AuthorBooksScreenState extends State<AuthorBooksScreen> {
  List<OpenLibraryBook>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _results = null;
      _error = null;
    });
    try {
      final name = widget.author.replaceAll('"', '');
      final found = await widget.client.search('author:"$name"');
      if (!mounted) return;
      setState(() => _results = _withoutOwned(found));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach Open Library. '
            'Check your connection and try again.';
      });
    }
  }

  List<OpenLibraryBook> _withoutOwned(List<OpenLibraryBook> found) {
    final ownedTitles = {
      for (final book in widget.repository.allBooks) _key(book.title),
    };
    final ownedIsbns = {
      for (final book in widget.repository.allBooks)
        if (book.isbn != null) book.isbn,
    };
    final seen = <String>{};
    return [
      for (final book in found)
        if (!ownedTitles.contains(_key(book.title)) &&
            !ownedIsbns.contains(book.isbn) &&
            seen.add(_key(book.title)))
          book,
    ];
  }

  Future<void> _add(OpenLibraryBook result) async {
    final shelf = await chooseShelfForNewBook(context, widget.settings);
    if (shelf == null || !mounted) return;
    await widget.repository.add(
      title: result.title,
      author: result.author,
      shelf: shelf,
      tags: widget.settings.defaultTags,
      format: widget.settings.defaultFormat,
      isbn: result.isbn,
      coverUrl: result.coverUrl,
      firstPublishYear: result.firstPublishYear,
      pages: result.pages,
    );
    if (!mounted) return;
    setState(() => _results = _withoutOwned(_results ?? const []));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${result.title}" to ${shelf.label}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text('More by ${widget.author}')),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : results == null
              ? const Center(child: CircularProgressIndicator())
              : results.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No other books found. You may already have them all.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        return ListTile(
                          leading: BookCover(coverUrl: result.coverUrl),
                          title: Text(result.title),
                          subtitle: Text(result.subtitle),
                          trailing: const Icon(Icons.add),
                          onTap: () => _add(result),
                        );
                      },
                    ),
    );
  }
}
