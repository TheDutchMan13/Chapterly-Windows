import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/notes_search.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';

// Windows app only.

/// Every quote and note, filtered by kind; type to search everything you
/// wrote or marked: notes, quotes, highlights and
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
  _Kind _kind = _Kind.all;
  late List<NoteDocument> _documents = _collect();

  List<NoteDocument> _collect() => collectNotes(
        widget.repository.books,
        ebooks: EbookReading.library?.links ?? const {},
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
    final searching = _query.text.trim().isNotEmpty;
    final textTheme = Theme.of(context).textTheme;
    // With no words typed, every note and quote is shown, newest book first.
    final List<({NoteDocument doc, Set<String> terms})> rows = searching
        ? [
            for (final hit in searchNotes(_documents, _query.text))
              if (_kind.includes(hit.document.source))
                (doc: hit.document, terms: hit.terms),
          ]
        : [
            for (final doc in _documents)
              if (_kind.includes(doc.source)) (doc: doc, terms: const <String>{}),
          ];
    int count(_Kind kind) =>
        _documents.where((d) => kind.includes(d.source)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Quotes and notes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search words from a quote, highlight or note',
                helperText: 'Typos are forgiven.',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final kind in _Kind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${kind.label} · ${count(kind)}'),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        searching
                            ? 'Nothing found.'
                            : 'No quotes or notes yet. Add them on a book '
                                'page, or highlight text while reading.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _NoteCard(
                        doc: row.doc,
                        text: _marked(
                          row.doc.text,
                          row.terms,
                          row.doc.source.isQuote
                              ? textTheme.titleMedium
                              : textTheme.bodyMedium,
                        ),
                        onTap: () => _open(row.doc),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _open(NoteDocument doc) {
    Navigator.of(context).pop();
    widget.onOpenBook(doc.book);
  };
}

/// Which notes to show.
enum _Kind {
  all('All'),
  quotes('Quotes'),
  notes('Notes');

  const _Kind(this.label);
  final String label;

  bool includes(NoteSource source) => switch (this) {
        _Kind.all => true,
        _Kind.quotes => source.isQuote,
        _Kind.notes => !source.isQuote,
      };
}

extension on NoteSource {
  /// Quotes and highlights: text from the book, not your own words.
  bool get isQuote => this == NoteSource.quote || this == NoteSource.highlight;
}

/// One quote or note: quotes larger with a line down the side, and the book
/// it is from underneath.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.doc, required this.text, required this.onTap});

  final NoteDocument doc;
  final Widget text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final quote = doc.source.isQuote;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: quote
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colours.primary, width: 4),
                  ),
                )
              : null,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doc.source.label.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: quote ? colours.primary : colours.tertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              text,
              const SizedBox(height: 8),
              Text(
                [
                  doc.book.title,
                  if (doc.book.author.isNotEmpty) doc.book.author,
                ].join(' · '),
                style: textTheme.bodySmall
                    ?.copyWith(color: colours.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
