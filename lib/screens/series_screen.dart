import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/series.dart';
import '../data/series_detect.dart';
import '../models/book.dart';
import '../models/shelf.dart';

// Windows app only.

/// Your series: which books you have, which you have finished, which numbers
/// are missing (add them to For later with one click), and what to read next.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.repository,
    required this.onOpenBook,
  });

  final BookRepository repository;
  final void Function(Book book) onOpenBook;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  bool _hideComplete = false;

  Future<void> _addMissing(SeriesInfo series, int number) async {
    final title = '${series.name} #$number';
    await widget.repository.add(
      title: title,
      author: series.author,
      shelf: Shelf.forLater,
    );
    final added = widget.repository.allBooks.firstOrNull;
    if (added == null || added.title != title) return;
    await widget.repository.setSeries(added.id, series.name, number);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added "$title" to For later. Change its title any time.'),
    ));
  }

  Future<void> _findInTitles() async {
    final guesses = detectSeries(widget.repository.allBooks);
    final messenger = ScaffoldMessenger.of(context);
    if (guesses.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No series found in the titles of books without one.'),
      ));
      return;
    }
    final chosen = await showDialog<List<SeriesGuess>>(
      context: context,
      builder: (_) => _SeriesGuessDialog(guesses: guesses),
    );
    if (chosen == null || chosen.isEmpty) return;
    for (final guess in chosen) {
      await widget.repository.setSeries(guess.book.id, guess.series, guess.number);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(
        'Set the series of ${chosen.length} '
        '${chosen.length == 1 ? 'book' : 'books'}.',
      ),
    ));
  }

  Widget _bookChip(Book book) {
    final done = book.shelf == Shelf.finished;
    final reading = book.shelf == Shelf.inProgress;
    return Tooltip(
      message: '${book.title} · ${book.shelf.label}',
      child: ActionChip(
        avatar: Icon(
          done
              ? Icons.check_circle
              : reading
                  ? Icons.auto_stories
                  : Icons.radio_button_unchecked,
          size: 18,
        ),
        label: Text(
          book.seriesNumber == null ? book.title : '#${book.seriesNumber}',
        ),
        onPressed: () {
          Navigator.of(context).pop();
          widget.onOpenBook(book);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series'),
        actions: [
          TextButton.icon(
            onPressed: _findInTitles,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Find series in titles'),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              const Text('Hide finished series'),
              Switch(
                value: _hideComplete,
                onChanged: (value) => setState(() => _hideComplete = value),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) {
          final all = seriesOverview(widget.repository.allBooks);
          final shown = [
            for (final series in all)
              if (!_hideComplete || !series.complete) series,
          ];
          if (all.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No series yet. Set a series and number on a book '
                  '(Overview tab) and it shows up here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final series = shown[index];
              final next = series.next;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(series.name, style: textTheme.titleMedium),
                      Text(
                        [
                          if (series.author.isNotEmpty) series.author,
                          '${series.finished} of ${series.total} finished',
                          if (series.missing.isNotEmpty)
                            '${series.missing.length} missing',
                        ].join(' · '),
                        style: textTheme.bodySmall,
                      ),
                      if (series.total > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            value: series.finished / series.total,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final book in series.books) _bookChip(book),
                          for (final number in series.missing)
                            Tooltip(
                              message: 'You do not have #$number. '
                                  'Click to add it to For later.',
                              child: ActionChip(
                                avatar: const Icon(Icons.add, size: 18),
                                label: Text('#$number'),
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                onPressed: () => _addMissing(series, number),
                              ),
                            ),
                          for (final book in series.unnumbered) _bookChip(book),
                        ],
                      ),
                      if (next != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Next: #${next.seriesNumber} ${next.title}',
                            style: textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The series found in titles, each with a check box.
class _SeriesGuessDialog extends StatefulWidget {
  const _SeriesGuessDialog({required this.guesses});

  final List<SeriesGuess> guesses;

  @override
  State<_SeriesGuessDialog> createState() => _SeriesGuessDialogState();
}

class _SeriesGuessDialogState extends State<_SeriesGuessDialog> {
  late final Set<SeriesGuess> _chosen = {...widget.guesses};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Series found in titles'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Uncheck any that are wrong. Only the series and number are '
                'set; titles stay as they are.',
              ),
            ),
            for (final guess in widget.guesses)
              CheckboxListTile(
                dense: true,
                value: _chosen.contains(guess),
                onChanged: (on) => setState(
                  () => on == true ? _chosen.add(guess) : _chosen.remove(guess),
                ),
                title: Text(guess.describe()),
                subtitle: Text(guess.book.title),
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
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                    for (final guess in widget.guesses)
                      if (_chosen.contains(guess)) guess,
                  ]),
          child: Text('Set ${_chosen.length}'),
        ),
      ],
    );
  }
}
