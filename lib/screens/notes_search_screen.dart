import 'package:flutter/material.dart';

import '../audio/audio_bookmarks.dart';
import '../data/book_repository.dart';
import '../data/notes_search.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';

// Windows app only.

/// Searches everything you wrote or marked: notes, quotes, highlights and
/// their notes, and audiobook bookmark notes, best match first.
class NotesSearchScreen extends StatefulWidget {
  const NotesSearchScreen({
    super.key,
    required this.repository,
    required this.onOpenBook,
  });

  final BookRepository repository;
  final void Function(Book book) onOpenBook;

  @override
  State<NotesSearchScreen> createState() => _NotesSearchScreenState();
}

class _NotesSearchScreenState extends State<NotesSearchScreen> {
  final _query = TextEditingController();
  late List<NoteDocument> _documents = _collect();

  List<NoteDocument> _collect() => collectNotes(
        widget.repository.books,
        ebooks: EbookReading.library?.links ?? const {},
        bookmarks: AudioBookmarking.store,
      );

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_refresh);
  }

  void _refresh() => setState(() => _documents = _collect());

  @override
  void dispose() {
    widget.repository.removeListener(_refresh);
    _query.dispose();
    super.dispose();
  }

  /// The text with the matched words in bold.
  Widget _marked(String text, Set<String> terms, TextStyle? style) {
    final spans = <TextSpan>[];
    for (final match in RegExp(r'[\p{L}\p{N}]+|[^\p{L}\p{N}]+', unicode: true)
        .allMatches(text)) {
      final part = match.group(0)!;
      spans.add(TextSpan(
        text: part,
        style: isMatchedWord(part, terms)
            ? const TextStyle(fontWeight: FontWeight.bold)
            : null,
      ));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchNotes(_documents, _query.text);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Search notes and quotes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Words from a quote, highlight or note',
                helperText: '${_documents.length} notes, quotes and '
                    'highlights. Typos are forgiven.',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _query.text.trim().isEmpty
                ? const SizedBox.shrink()
                : hits.isEmpty
                    ? const Center(child: Text('Nothing found.'))
                    : ListView.separated(
                        itemCount: hits.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final hit = hits[index];
                          final doc = hit.document;
                          return ListTile(
                            title: _marked(doc.text, hit.terms, textTheme.bodyMedium),
                            subtitle: Text(
                              '${doc.source.label} · ${doc.book.title}'
                              '${doc.book.author.isEmpty ? '' : ' · ${doc.book.author}'}',
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onOpenBook(doc.book);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
