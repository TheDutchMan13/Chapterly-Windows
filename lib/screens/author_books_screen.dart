import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/author_page.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';
import 'shelf_picker.dart';

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// An author's page: what you have read by them, your books by them, and
/// their other books from Open Library, leaving out the ones you already
/// have. Tap an Open Library book to add it to a shelf.
class AuthorBooksScreen extends StatefulWidget {
  const AuthorBooksScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.author,
    required this.settings,
    required this.fileIo,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final String author;
  final AppSettings settings;
  final FileIo fileIo;

  @override
  State<AuthorBooksScreen> createState() => _AuthorBooksScreenState();
}

class _AuthorBooksScreenState extends State<AuthorBooksScreen> {
  List<OpenLibraryBook>? _found;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _found = null;
      _error = null;
    });
    try {
      final name = widget.author.replaceAll('"', '');
      final found = await widget.client.search('author:"$name"');
      if (!mounted) return;
      setState(() => _found = found);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${result.title}" to ${shelf.label}')),
    );
  }

  void _open(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
          bookId: book.id,
        ),
      ),
    );
  }

  String _ownedSubtitle(Book book) => [
        book.shelf.label,
        if (book.series case final series? when series.trim().isNotEmpty)
          book.seriesNumber == null
              ? series.trim()
              : '${series.trim()} #${book.seriesNumber}',
        if (book.rating case final rating?) '$rating★',
        if (book.finishedAt case final date?) 'finished ${date.year}',
      ].join(' · ');

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.author)),
      body: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) {
          final owned = booksByAuthor(widget.repository.books, widget.author);
          final summary = summarizeAuthor(owned);
          final found = _found;
          final error = _error;
          final others = found == null ? null : _withoutOwned(found);
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  owned.isEmpty
                      ? 'You have no books by ${widget.author} yet.'
                      : summary.describe(),
                ),
              ),
              if (owned.isNotEmpty) ...[
                _header(context, 'Your books'),
                for (final book in owned)
                  ListTile(
                    leading: BookCover(
                      coverUrl: book.coverUrl,
                      title: book.title,
                    ),
                    title: Text(book.title),
                    subtitle: Text(_ownedSubtitle(book)),
                    onTap: () => _open(book),
                  ),
              ],
              _header(context, 'Not in your library'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (others == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (others.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No other books found on Open Library. You may already '
                    'have them all.',
                  ),
                )
              else
                for (final result in others)
                  ListTile(
                    leading: BookCover(coverUrl: result.coverUrl),
                    title: Text(result.title),
                    subtitle: Text(result.subtitle),
                    trailing: const Icon(Icons.add),
                    onTap: () => _add(result),
                  ),
            ],
          );
        },
      ),
    );
  }
}
