import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/open_library_client.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'shelf_picker.dart';

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Books on the same subjects as [book], from Open Library, leaving out the
/// ones you already have. Pick a subject at the top, tap a book to add it.
class SubjectBooksScreen extends StatefulWidget {
  const SubjectBooksScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.settings,
    required this.book,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;
  final Book book;

  @override
  State<SubjectBooksScreen> createState() => _SubjectBooksScreenState();
}

class _SubjectBooksScreenState extends State<SubjectBooksScreen> {
  List<String>? _subjects;
  String? _subject;
  List<OpenLibraryBook>? _results;
  String? _error;

  static const _offline =
      'Could not reach Open Library. Check your connection and try again.';

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _subjects = null;
      _error = null;
    });
    try {
      final subjects = await widget.client.subjectsFor(
        title: widget.book.title,
        author: widget.book.author,
        isbn: widget.book.isbn,
      );
      if (!mounted) return;
      setState(() => _subjects = subjects);
      if (subjects.isNotEmpty) await _loadSubject(subjects.first);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _offline);
    }
  }

  Future<void> _loadSubject(String subject) async {
    setState(() {
      _subject = subject;
      _results = null;
      _error = null;
    });
    try {
      final found = await widget.client.searchSubject(subject);
      if (!mounted || _subject != subject) return;
      setState(() => _results = _withoutOwned(found));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _offline);
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

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final subject = _subject;
                  if (subject == null) {
                    _loadSubjects();
                  } else {
                    _loadSubject(subject);
                  }
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final subjects = _subjects;
    if (subjects == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (subjects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Open Library lists no subjects for this book, so there is '
            'nothing to compare it with.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final results = _results;
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: subjects.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final subject = subjects[index];
              return ChoiceChip(
                label: Text(subject),
                selected: subject == _subject,
                onSelected: (_) => _loadSubject(subject),
              );
            },
          ),
        ),
        Expanded(
          child: results == null
              ? const Center(child: CircularProgressIndicator())
              : results.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No new books found for this subject.',
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Books like ${widget.book.title}')),
      body: _body(),
    );
  }
}
