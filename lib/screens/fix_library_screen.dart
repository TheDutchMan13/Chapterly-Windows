import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/cover_size.dart';
import '../data/cover_update.dart';
import '../data/file_details.dart';
import '../data/google_books_client.dart';
import '../data/hardcover_client.dart';
import '../data/isbn_update.dart';
import '../data/open_library_client.dart';
import '../data/series.dart';
import '../models/book.dart';
import '../widgets/book_cover.dart';

// The same file is in the Android app; keep the two copies alike.

/// The steps of Fix library, in the order they run and are applied.
enum FixStep {
  seriesNames('Series spelled two ways', 'Joins "Dexter" and "Dexter Series".'),
  files('From your book files',
      'Series, ISBN and cover written inside your EPUB and M4B files, or known '
      'to your book server.'),
  hardcover('Series from Hardcover',
      'Looks up books with no series. Needs a Hardcover token in Settings.'),
  isbns('ISBNs', 'Looks up books with no ISBN on Open Library.'),
  covers('Covers',
      'Books with no cover, or a broken Open Library one. Asks Google Books too '
      'when Open Library has none.'),
  largerCovers('Larger covers',
      'Swaps small Open Library and Google covers for their larger pictures. '
      'No lookups.');

  const FixStep(this.label, this.detail);

  final String label;
  final String detail;
}

/// One change Fix library found, to be applied when chosen.
class LibraryFix {
  LibraryFix({
    required this.step,
    required this.title,
    required this.detail,
    required this.apply,
    this.book,
    this.coverUrl,
  });

  final FixStep step;
  final String title;
  final String detail;
  final Book? book;

  /// A new cover to show next to it.
  final String? coverUrl;
  final Future<void> Function() apply;
}

/// Runs the library tools one after the other (series spellings, your book
/// files, Hardcover, ISBNs, covers, larger covers) and shows everything they
/// found in one list. Nothing changes until you press Apply, and only what
/// is ticked.
class FixLibraryScreen extends StatefulWidget {
  const FixLibraryScreen({
    super.key,
    required this.repository,
    required this.client,
    this.hardcover,
    this.google,
  });

  final BookRepository repository;
  final OpenLibraryClient client;

  /// Null to use the shared ones.
  final HardcoverClient? hardcover;
  final GoogleBooksClient? google;

  @override
  State<FixLibraryScreen> createState() => _FixLibraryScreenState();
}

class _FixLibraryScreenState extends State<FixLibraryScreen> {
  late final _hardcover = widget.hardcover ?? hardcoverClient;
  late final _google = widget.google ?? googleBooksClient;
  late final Set<FixStep> _steps = {
    for (final step in FixStep.values)
      if (step != FixStep.hardcover || _hardcover.hasToken) step,
  };
  bool _running = false;
  bool _cancel = false;
  bool _done = false;
  String _status = '';
  double? _progress;
  final List<LibraryFix> _fixes = [];
  final Set<LibraryFix> _chosen = {};
  final List<String> _notes = [];

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  List<Book> get _books => [
        for (final book in widget.repository.allBooks)
          if (book.deletedAt == null) book,
      ];

  void _found(LibraryFix fix) {
    if (!mounted) return;
    setState(() {
      _fixes.add(fix);
      _chosen.add(fix);
    });
  }

  void _show(String status, [int done = 0, int total = 0]) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _progress = total == 0 ? null : done / total;
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _cancel = false;
      _done = false;
      _fixes.clear();
      _chosen.clear();
      _notes.clear();
    });
    final repository = widget.repository;
    // Books a step already fills, so a later step does not fill them again.
    final hasSeries = <String>{};
    final hasIsbn = <String>{};
    final hasCover = <String>{};

    if (_steps.contains(FixStep.seriesNames) && !_cancel) {
      _show('Looking for series spelled two ways');
      final books = {for (final book in _books) book.id: book};
      for (final merge in findSeriesMerges(books.values.toList())) {
        _found(LibraryFix(
          step: FixStep.seriesNames,
          title: '${merge.names.join(', ')} → ${merge.target}',
          detail: '${merge.count} ${merge.count == 1 ? 'book' : 'books'}',
          apply: () => repository.setSeriesFor({
            for (final id in merge.bookIds)
              if (books[id] case final book?) id: (merge.target, book.seriesNumber),
          }),
        ));
      }
    }

    if (_steps.contains(FixStep.files) && !_cancel) {
      final books = _books;
      for (var i = 0; i < books.length && !_cancel; i++) {
        _show('Reading your book files', i, books.length);
        final fix = await fileDetailsFor(books[i]);
        if (fix == null) continue;
        if (fix.series != null) hasSeries.add(fix.book.id);
        if (fix.isbn != null) hasIsbn.add(fix.book.id);
        if (fix.coverUrl != null) hasCover.add(fix.book.id);
        _found(LibraryFix(
          step: FixStep.files,
          book: fix.book,
          title: fix.book.title,
          detail: '${fix.summary} · from ${fix.source}',
          coverUrl: fix.coverUrl,
          apply: () => repository.fillBlanks(
            fix.book.id,
            series: fix.series,
            seriesNumber: fix.seriesNumber,
            isbn: fix.isbn,
            coverUrl: fix.coverUrl,
          ),
        ));
      }
    }

    if (_steps.contains(FixStep.hardcover) && !_cancel) {
      final books = [
        for (final book in _books)
          if ((book.series ?? '').trim().isEmpty && !hasSeries.contains(book.id))
            book,
      ];
      var failures = 0;
      for (var i = 0; i < books.length && !_cancel; i++) {
        _show('Asking Hardcover for series', i, books.length);
        final book = books[i];
        try {
          final found = await _hardcover.seriesFor(book);
          failures = 0;
          if (found == null) continue;
          _found(LibraryFix(
            step: FixStep.hardcover,
            book: book,
            title: book.title,
            detail: found.number == null
                ? 'Series ${found.series}'
                : 'Series ${found.series} #${found.number}',
            apply: () => repository.fillBlanks(
              book.id,
              series: found.series,
              seriesNumber: found.number,
            ),
          ));
        } on HardcoverUnauthorized {
          _notes.add('Hardcover did not accept the token. Check it in '
              'Settings.');
          break;
        } catch (_) {
          if (++failures >= 3) {
            _notes.add('Hardcover could not be reached.');
            break;
          }
        }
      }
    }

    if (_steps.contains(FixStep.isbns) && !_cancel) {
      final books = [
        for (final book in booksWithoutIsbn(_books))
          if (!hasIsbn.contains(book.id)) book,
      ];
      final result = await scanIsbns(
        books,
        widget.client,
        cancelled: () => _cancel,
        onProgress: (done, total) => _show('Looking up ISBNs', done, total),
        onFix: (fix) => _found(LibraryFix(
          step: FixStep.isbns,
          book: fix.book,
          title: fix.book.title,
          detail: 'ISBN ${fix.isbn}',
          apply: () => repository.fillBlanks(fix.book.id, isbn: fix.isbn),
        )),
      );
      if (result.unreachable) _notes.add('Open Library could not be reached.');
    }

    if (_steps.contains(FixStep.covers) && !_cancel) {
      final books = [
        for (final book in coverCandidates(_books))
          if (!hasCover.contains(book.id)) book,
      ];
      final result = await scanCovers(
        books,
        widget.client,
        google: _google,
        cancelled: () => _cancel,
        onProgress: (done, total) => _show('Looking for covers', done, total),
        onFix: (fix) {
          hasCover.add(fix.book.id);
          final url = largerCover(fix.newUrl);
          _found(LibraryFix(
            step: FixStep.covers,
            book: fix.book,
            title: fix.book.title,
            detail: '${fix.problem == CoverProblem.missing ? 'No cover yet' : 'Broken cover'} · ${fix.source}',
            coverUrl: url,
            apply: () => repository.setCoversFor({fix.book.id: url}),
          ));
        },
      );
      if (result.googleQuotaReached) {
        _notes.add('Google Books ran out of searches for today.');
      }
      if (result.unreachable) _notes.add('Open Library could not be reached.');
    }

    if (_steps.contains(FixStep.largerCovers) && !_cancel) {
      _show('Looking for small covers');
      for (final book in _books) {
        final url = book.coverUrl;
        if (hasCover.contains(book.id) || !hasLargerCover(url)) continue;
        final bigger = largerCover(url!);
        _found(LibraryFix(
          step: FixStep.largerCovers,
          book: book,
          title: book.title,
          detail: 'A larger picture of the same cover',
          coverUrl: bigger,
          apply: () => repository.setCoversFor({book.id: bigger}),
        ));
      }
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _done = true;
      _progress = null;
      _status = _cancel ? 'Stopped.' : 'Done.';
    });
  }

  Future<void> _apply() async {
    final chosen = [
      for (final step in FixStep.values)
        for (final fix in _fixes)
          if (fix.step == step && _chosen.contains(fix)) fix,
    ];
    for (final fix in chosen) {
      await fix.apply();
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(
        'Applied ${chosen.length} ${chosen.length == 1 ? 'change' : 'changes'}.',
      ),
    ));
    setState(() {
      _fixes.removeWhere(chosen.contains);
      _chosen.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Fix library')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'Runs the library tools one after the other and shows '
              'everything they found here. Nothing changes until you press '
              'Apply, and only what is ticked. Only blank details are filled '
              'in, except broken and small covers.',
              style: textTheme.bodyMedium
                  ?.copyWith(color: colours.onSurfaceVariant),
            ),
          ),
          if (!_running && !_done)
            for (final step in FixStep.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _steps.contains(step),
                onChanged: step == FixStep.hardcover && !_hardcover.hasToken
                    ? null
                    : (value) => setState(() {
                          if (value ?? false) {
                            _steps.add(step);
                          } else {
                            _steps.remove(step);
                          }
                        }),
                title: Text(step.label),
                subtitle: Text(
                  step == FixStep.hardcover && !_hardcover.hasToken
                      ? 'Add a Hardcover token in Settings to use this.'
                      : step.detail,
                ),
              ),
          if (_running) ...[
            LinearProgressIndicator(value: _progress),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(_status)),
                  TextButton(
                    onPressed: () => setState(() => _cancel = true),
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _steps.isEmpty ? null : _run,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: Text(_done ? 'Check again' : 'Check my library'),
                ),
              ),
            ),
          if (_done) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                [
                  '$_status Found ${_fixes.length} '
                      '${_fixes.length == 1 ? 'change' : 'changes'}.',
                  ..._notes,
                ].join(' '),
                style: textTheme.bodyMedium,
              ),
            ),
          ],
          for (final step in FixStep.values)
            if (_fixes.any((fix) => fix.step == step)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${step.label} (${_fixes.where((f) => f.step == step).length})',
                        style: textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        final all = _fixes.where((f) => f.step == step);
                        if (all.every(_chosen.contains)) {
                          _chosen.removeAll(all);
                        } else {
                          _chosen.addAll(all);
                        }
                      }),
                      child: const Text('All / none'),
                    ),
                  ],
                ),
              ),
              for (final fix in _fixes)
                if (fix.step == step)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: CheckboxListTile(
                      value: _chosen.contains(fix),
                      onChanged: (value) => setState(() {
                        if (value ?? false) {
                          _chosen.add(fix);
                        } else {
                          _chosen.remove(fix);
                        }
                      }),
                      secondary: fix.book == null
                          ? null
                          : BookCover(
                              coverUrl: fix.coverUrl ?? fix.book!.coverUrl,
                              title: fix.book!.title,
                              width: 36,
                              height: 54,
                            ),
                      title: Text(
                        fix.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(fix.detail),
                    ),
                  ),
            ],
          if (_fixes.isNotEmpty && !_running)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton(
                onPressed: _chosen.isEmpty ? null : _apply,
                child: Text(
                  'Apply ${_chosen.length} '
                  '${_chosen.length == 1 ? 'change' : 'changes'}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
