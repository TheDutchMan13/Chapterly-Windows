// The same file is in both apps (lib/screens/series_check_screen.dart).

import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/hardcover_client.dart';
import '../data/series.dart';
import '../data/series_check.dart';
import '../models/shelf.dart';

/// Asks Hardcover about every series you have and lists the books you don't
/// have, newer ones first. Tick the ones to add to For later.
class SeriesCheckScreen extends StatefulWidget {
  const SeriesCheckScreen({
    super.key,
    required this.repository,
    required this.series,
  });

  final BookRepository repository;
  final List<SeriesInfo> series;

  @override
  State<SeriesCheckScreen> createState() => _SeriesCheckScreenState();
}

class _SeriesCheckScreenState extends State<SeriesCheckScreen> {
  int _done = 0;
  bool _cancelled = false;
  SeriesCheckResult? _result;
  String? _problem;
  final _chosen = <(SeriesGap, HardcoverSeriesBook)>{};

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final result = await checkAllSeries(
        widget.series,
        hardcoverClient,
        onProgress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
        cancelled: () => _cancelled,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        // Newer books are ticked to start with.
        for (final gap in result.gaps) {
          for (final book in gap.newer) {
            _chosen.add((gap, book));
          }
        }
      });
    } on HardcoverUnauthorized {
      if (mounted) {
        setState(() => _problem =
            'Hardcover did not accept the token. Check it in Settings.');
      }
    }
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final chosen = [..._chosen];
    for (final (gap, book) in chosen) {
      final id = await widget.repository.add(
        title: book.title,
        author: gap.series.author,
        shelf: Shelf.forLater,
      );
      await widget.repository.setSeries(id, gap.series.name, book.number);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(
        'Added ${chosen.length} ${chosen.length == 1 ? 'book' : 'books'} '
        'to For later.',
      ),
    ));
    navigator.pop();
  }

  bool _isChosen(SeriesGap gap, HardcoverSeriesBook book) =>
      _chosen.contains((gap, book));

  void _toggle(SeriesGap gap, HardcoverSeriesBook book, bool on) =>
      setState(() => on ? _chosen.add((gap, book)) : _chosen.remove((gap, book)));

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final textTheme = Theme.of(context).textTheme;
    final total = widget.series.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Check every series')),
      bottomNavigationBar: result == null || result.gaps.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _chosen.isEmpty ? null : _add,
                  child: Text(
                    'Add ${_chosen.length} to For later',
                  ),
                ),
              ),
            ),
      body: _problem != null
          ? Center(child: Text(_problem!))
          : result == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: total == 0 ? null : _done / total,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Asking Hardcover about series $_done of $total. '
                          'It allows about one a second.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(_summary(result)),
                    ),
                    for (final gap in result.gaps) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          gap.series.name,
                          style: textTheme.titleMedium,
                        ),
                      ),
                      for (final book in gap.missing)
                        CheckboxListTile(
                          value: _isChosen(gap, book),
                          onChanged: (on) => _toggle(gap, book, on ?? false),
                          title: Text('#${book.number} ${book.title}'),
                          subtitle: book.number > gap.highestOwned
                              ? const Text('After the last one you have')
                              : null,
                        ),
                    ],
                  ],
                ),
    );
  }

  String _summary(SeriesCheckResult result) {
    final parts = <String>[];
    final books = result.gaps.fold(0, (sum, gap) => sum + gap.missing.length);
    parts.add(result.gaps.isEmpty
        ? 'You have every book Hardcover lists in the ${result.checked} '
            'series checked.'
        : '$books ${books == 1 ? 'book' : 'books'} you don\'t have, in '
            '${result.gaps.length} of ${result.checked} series. Books after '
            'the last one you have are ticked.');
    if (result.notFound.isNotEmpty) {
      parts.add('Hardcover doesn\'t know: ${result.notFound.join(', ')}.');
    }
    if (result.failed.isNotEmpty) {
      parts.add('Could not check: ${result.failed.join(', ')}.');
    }
    return parts.join('\n\n');
  }
}
