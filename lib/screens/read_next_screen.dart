import 'dart:math';

import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';

/// Picks a random book from the For later shelf, so you do not have to.
class ReadNextScreen extends StatefulWidget {
  const ReadNextScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;

  @override
  State<ReadNextScreen> createState() => _ReadNextScreenState();
}

class _ReadNextScreenState extends State<ReadNextScreen> {
  final _random = Random();
  final Set<String> _tags = {};
  final Set<BookFormat> _formats = {};
  String? _currentId;

  List<Book> _candidates() => widget.repository.booksOn(
        Shelf.forLater,
        tags: _tags,
        formats: _formats,
      );

  Book? _choose(List<Book> candidates, {String? avoid}) {
    if (candidates.isEmpty) return null;
    final pool = candidates.length > 1
        ? [
            for (final book in candidates)
              if (book.id != avoid) book,
          ]
        : candidates;
    return pool[_random.nextInt(pool.length)];
  }

  void _pickAnother(List<Book> candidates) {
    setState(() => _currentId = _choose(candidates, avoid: _currentId)?.id);
  }

  Future<void> _start(Book book) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await widget.repository.moveTo(book.id, Shelf.inProgress);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Started "${book.title}"')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What should I read next?')),
      body: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) {
          final waiting = widget.repository.booksOn(Shelf.forLater);
          final tags = ({for (final book in waiting) ...book.tags}.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
          final candidates = _candidates();
          Book? current;
          for (final book in candidates) {
            if (book.id == _currentId) current = book;
          }
          current ??= _choose(candidates);
          _currentId = current?.id;
          final shown = current;
          final textTheme = Theme.of(context).textTheme;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (waiting.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Text(
                    'Nothing on your For later shelf yet. Add some books '
                    'there and come back.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final format in BookFormat.values)
                      FilterChip(
                        label: Text(format.label),
                        selected: _formats.contains(format),
                        onSelected: (on) => setState(
                          () => on
                              ? _formats.add(format)
                              : _formats.remove(format),
                        ),
                      ),
                    for (final tag in tags)
                      FilterChip(
                        label: Text(tag),
                        selected: _tags.contains(tag),
                        onSelected: (on) => setState(
                          () => on ? _tags.add(tag) : _tags.remove(tag),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (shown == null)
                  const Text(
                    'No book on For later matches those filters.',
                    textAlign: TextAlign.center,
                  )
                else ...[
                  Center(
                    child: BookCover(
                      coverUrl: shown.coverUrl,
                      width: 140,
                      height: 210,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    shown.title,
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall,
                  ),
                  if (shown.author.isNotEmpty)
                    Text(shown.author, textAlign: TextAlign.center),
                  Text(
                    [
                      if (shown.pages != null) '${shown.pages} pages',
                      if (shown.format != null) shown.format!.label,
                    ].join(' · '),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _start(shown),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start reading'),
                      ),
                      OutlinedButton.icon(
                        onPressed: candidates.length > 1
                            ? () => _pickAnother(candidates)
                            : null,
                        icon: const Icon(Icons.casino_outlined),
                        label: const Text('Pick another'),
                      ),
                      TextButton(
                        onPressed: () => _open(shown),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
