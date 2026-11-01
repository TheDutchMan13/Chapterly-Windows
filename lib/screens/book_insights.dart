import 'package:flutter/material.dart';

import '../audio/listening.dart';
import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/forecast.dart';
import '../data/format_sync.dart';
import '../data/open_library_client.dart';
import '../data/rating_predict.dart';
import '../data/reading_time.dart';
import '../data/recommend.dart';
import '../data/tag_suggest.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import 'reader_screen.dart';
import 'similar_books_screen.dart';

// Windows app only: the book page's forecast, format sync, tag suggestions
// and similar books.

/// The finish forecast for a book you are reading, from your recent pace.
FinishForecast? forecastFor(Book book) {
  final audio = Listening.controller?.library;
  return forecastFinish(
    book,
    audio: audio?.linkFor(book.id),
    speed: audio?.speed ?? 1,
    ebook: EbookReading.library?.linkFor(book.id),
  );
}

/// Your reading speed, from the whole library and the reader.
ReadingSpeed speedFor(BookRepository repository) => readingSpeed(
      repository.books,
      ebooks: EbookReading.library?.links ?? const {},
    );

/// How long [book] takes you, at your speed.
ReadingTime? readingTimeFor(Book book, ReadingSpeed pace) {
  final audio = Listening.controller?.library;
  return readingTime(
    book,
    pace: pace,
    audio: audio?.linkFor(book.id),
    speed: audio?.speed ?? 1,
  );
}

/// "About 9 h to read (at your 38 pages an hour)".
class ReadingTimeTile extends StatelessWidget {
  const ReadingTimeTile({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final BookRepository repository;

  @override
  Widget build(BuildContext context) {
    if (book.shelf == Shelf.finished) return const SizedBox.shrink();
    final pace = speedFor(repository);
    final time = readingTimeFor(book, pace);
    if (time == null) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule_outlined),
      title: const Text('Reading time'),
      subtitle: Text(time.describe(pagesPerHour: pace.pagesPerHour)),
    );
  }
}

/// "You'd probably give this 4.2★" for a book you have not rated.
class PredictedRatingTile extends StatelessWidget {
  const PredictedRatingTile({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final BookRepository repository;

  @override
  Widget build(BuildContext context) {
    if (book.rating != null || book.shelf == Shelf.finished) {
      return const SizedBox.shrink();
    }
    final guess = predictRating(repository.books, book);
    if (guess == null) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.star_half_outlined),
      title: const Text('Predicted rating'),
      subtitle: Text(guess.describe()),
    );
  }
}

/// "Finish forecast: about 12 days left · finish around ...".
class FinishForecastTile extends StatelessWidget {
  const FinishForecastTile({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final forecast = forecastFor(book);
    if (forecast == null) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_available_outlined),
      title: const Text('Finish forecast'),
      subtitle: Text(forecast.describe()),
    );
  }
}

/// Shown when a book has both an audiobook and a book file and they are at
/// different places: carry on in one from where you are in the other.
class FormatSyncCard extends StatelessWidget {
  const FormatSyncCard({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final BookRepository repository;

  String _percent(double value) => '${(value * 100).round()}%';

  Future<void> _readFrom(BuildContext context, double fraction) async {
    final library = EbookReading.library;
    final link = library?.linkFor(book.id);
    if (library == null || link == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final position = await readerPositionAt(link, fraction);
    if (position == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't find that place in the book file."),
      ));
      return;
    }
    await library.setPosition(book.id, position);
    if (!context.mounted) return;
    openReader(context, repository: repository, library: library, bookId: book.id);
  }

  Future<void> _listenFrom(BuildContext context, double fraction) async {
    final controller = Listening.controller;
    final link = controller?.library.linkFor(book.id);
    if (controller == null || link == null || link.lengthMs == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final progress = audioProgressAt(link, fraction);
    if (controller.bookId == book.id) {
      await controller.seekTo(
        progress.track,
        Duration(milliseconds: progress.trackMs),
      );
      await controller.play();
      return;
    }
    await repository.setAudioProgress(book.id, progress);
    final problem = await controller.open(book.id);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioLibrary = Listening.controller?.library;
    final ebookLibrary = EbookReading.library;
    if (audioLibrary == null || ebookLibrary == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: Listenable.merge([audioLibrary, ebookLibrary]),
      builder: (context, _) {
        final places = formatPositions(
          book,
          audio: audioLibrary.linkFor(book.id),
          ebook: ebookLibrary.linkFor(book.id),
        );
        if (places == null || !places.apart) return const SizedBox.shrink();
        final textTheme = Theme.of(context).textTheme;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync_alt, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Audiobook at ${_percent(places.audio)}, '
                        'book file at ${_percent(places.reader)}',
                        style: textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Carry on in one from where you are in the other. The '
                  'place is worked out by how far through the book you are, '
                  'so it can be a page or two off.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (places.audioAhead)
                      FilledButton.tonalIcon(
                        onPressed: () => _readFrom(context, places.audio),
                        icon: const Icon(Icons.chrome_reader_mode_outlined),
                        label: Text('Read from ${_percent(places.audio)}'),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: () => _listenFrom(context, places.reader),
                        icon: const Icon(Icons.headphones_outlined),
                        label: Text('Listen from ${_percent(places.reader)}'),
                      ),
                    if (places.audioAhead)
                      TextButton(
                        onPressed: () => _listenFrom(context, places.reader),
                        child: Text(
                          'Or listen from ${_percent(places.reader)}',
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () => _readFrom(context, places.audio),
                        child: Text('Or read from ${_percent(places.audio)}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Opens a list of the books in your library most like [book].
void showSimilarInLibrary(
  BuildContext context, {
  required BookRepository repository,
  required AppSettings settings,
  required FileIo fileIo,
  required Book book,
}) {
  final similar = similarBooks(repository.books, book, limit: 20);
  final rank = {
    for (var i = 0; i < similar.length; i++) similar[i].$1.id: i,
  };
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SimilarBooksScreen(
        repository: repository,
        settings: settings,
        fileIo: fileIo,
        title: 'Like ${book.title}',
        test: (other) => rank.containsKey(other.id),
        compare: (a, b) => rank[a.id]!.compareTo(rank[b.id]!),
      ),
    ),
  );
}

/// Suggests tags for [book] from Open Library's subjects and the tags on
/// books by the same author or in the same series, and adds the ones you
/// pick.
Future<void> showTagSuggestions(
  BuildContext context, {
  required BookRepository repository,
  required Book book,
  OpenLibraryClient? client,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TagSuggestionsDialog(
      repository: repository,
      book: book,
      client: client ?? OpenLibraryClient(),
    ),
  );
}

class _TagSuggestionsDialog extends StatefulWidget {
  const _TagSuggestionsDialog({
    required this.repository,
    required this.book,
    required this.client,
  });

  final BookRepository repository;
  final Book book;
  final OpenLibraryClient client;

  @override
  State<_TagSuggestionsDialog> createState() => _TagSuggestionsDialogState();
}

class _TagSuggestionsDialogState extends State<_TagSuggestionsDialog> {
  List<TagSuggestion>? _suggestions;
  final Set<String> _chosen = {};
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var subjects = <String>[];
    try {
      subjects = await widget.client.subjectsFor(
        title: widget.book.title,
        author: widget.book.author,
        isbn: widget.book.isbn,
      );
    } catch (_) {
      _offline = true;
    }
    final suggestions = suggestTags(
      widget.book,
      widget.repository.books,
      subjects: subjects,
    );
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _chosen.addAll([
        for (final s in suggestions)
          if (!s.isNew && s.score >= 0.75) s.tag,
      ]);
    });
  }

  Future<void> _add() async {
    final navigator = Navigator.of(context);
    final book = widget.repository.byId(widget.book.id) ?? widget.book;
    final have = {for (final tag in book.tags) tag.toLowerCase()};
    await widget.repository.setTags(book.id, [
      ...book.tags,
      for (final tag in _chosen)
        if (!have.contains(tag.toLowerCase())) tag,
    ]);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return AlertDialog(
      title: const Text('Suggested tags'),
      content: SizedBox(
        width: 420,
        child: suggestions == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : suggestions.isEmpty
                ? Text(
                    _offline
                        ? "Couldn't reach Open Library, and your library has "
                            'no tags that fit yet.'
                        : 'No tags to suggest for this book.',
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      if (_offline)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            "Couldn't reach Open Library; these come from "
                            'your own library.',
                          ),
                        ),
                      for (final s in suggestions)
                        CheckboxListTile(
                          value: _chosen.contains(s.tag),
                          onChanged: (on) => setState(
                            () => on == true
                                ? _chosen.add(s.tag)
                                : _chosen.remove(s.tag),
                          ),
                          title: Text(s.isNew ? '${s.tag} (new tag)' : s.tag),
                          subtitle: Text(s.reason),
                          dense: true,
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty ? null : _add,
          child: Text(_chosen.isEmpty ? 'Add' : 'Add ${_chosen.length}'),
        ),
      ],
    );
  }
}
