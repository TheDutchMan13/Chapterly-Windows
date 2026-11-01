import 'dart:math';

import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/rating_predict.dart';
import '../data/reading_time.dart';
import '../data/recommend.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'book_insights.dart';
import 'book_detail_screen.dart';

/// Picks a book from the For later shelf, so you do not have to: the best
/// match for your taste (Windows app), or a random one.
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

  /// Best match for your taste, or a surprise.
  bool _bestMatch = true;
  int _rank = 0;

  /// Only books you could read in this many minutes (Windows app), or null.
  int? _timeLimit;
  static const _timeChoices = [60, 180, 360, 720];

  List<Book> _candidates() {
    final books = widget.repository.booksOn(
      Shelf.forLater,
      tags: _tags,
      formats: _formats,
    );
    final limit = _timeLimit;
    if (limit == null) return books;
    final pace = speedFor(widget.repository);
    return [
      for (final fit in fitsInTime(books, limit, (b) => readingTimeFor(b, pace)))
        fit.book,
    ];
  }

  String _timeLabel(int minutes) =>
      minutes < 60 * 2 ? '${minutes ~/ 60} hour' : '${minutes ~/ 60} hours';

  Widget _timePicker() {
    final pace = speedFor(widget.repository);
    final limit = _timeLimit;
    final finishable = limit == null
        ? const <TimeFit>[]
        : fitsInTime(
            widget.repository.booksOn(Shelf.inProgress),
            limit,
            (b) => readingTimeFor(b, pace),
          );
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text('Time I have:'),
            ChoiceChip(
              label: const Text('Any'),
              selected: limit == null,
              onSelected: (_) => setState(() {
                _timeLimit = null;
                _rank = 0;
              }),
            ),
            for (final minutes in _timeChoices)
              ChoiceChip(
                label: Text(_timeLabel(minutes)),
                selected: limit == minutes,
                onSelected: (_) => setState(() {
                  _timeLimit = minutes;
                  _rank = 0;
                }),
              ),
          ],
        ),
        if (finishable.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Or finish one you are reading: ${[
              for (final fit in finishable.take(3))
                '${fit.book.title} (${fit.minutes < 60 ? '${fit.minutes} min' : '${(fit.minutes / 60).toStringAsFixed(1)} h'} left)',
            ].join(', ')}',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

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
          List<Recommendation> ranked = const [];
          Recommendation? recommendation;
          if (_bestMatch && candidates.isNotEmpty) {
            ranked = recommend(widget.repository.books, candidates);
            recommendation = ranked[_rank % ranked.length];
            current = recommendation.book;
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
                Center(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.auto_awesome_outlined),
                        label: Text('Best match'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.casino_outlined),
                        label: Text('Surprise me'),
                      ),
                    ],
                    selected: {_bestMatch},
                    onSelectionChanged: (choice) => setState(() {
                      _bestMatch = choice.first;
                      _rank = 0;
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                _timePicker(),
                const SizedBox(height: 16),
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
                  Text(
                    _timeLimit == null
                        ? 'No book on For later matches those filters.'
                        : 'No book on For later fits in that time (books need '
                            'a page count or audiobook length).',
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
                  if (recommendation != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      recommendation.describe(),
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (predictRating(widget.repository.books, shown)
                        case final guess?)
                      Text(guess.describe(), textAlign: TextAlign.center),
                    Text(
                      'Match ${_rank % ranked.length + 1} of ${ranked.length}',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall,
                    ),
                  ],
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
                            ? () => _bestMatch
                                ? setState(() => _rank++)
                                : _pickAnother(candidates)
                            : null,
                        icon: Icon(
                          _bestMatch ? Icons.skip_next : Icons.casino_outlined,
                        ),
                        label: Text(_bestMatch ? 'Next match' : 'Pick another'),
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
