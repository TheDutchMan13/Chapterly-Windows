import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/cover_hash.dart';
import '../data/duplicates.dart';
import '../data/library_health.dart';
import '../data/stalled.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import 'duplicates_screen.dart';

// Windows app only.

/// Everything that looks wrong or missing in the library, with a click to
/// open each book, plus stalled books, duplicates and a cover check.
class LibraryHealthScreen extends StatefulWidget {
  const LibraryHealthScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.onOpenBook,
    this.coverPrints,
  });

  final BookRepository repository;
  final AppSettings settings;
  final void Function(Book book) onOpenBook;

  /// Where cover fingerprints are kept; made from the app folder when null.
  final CoverPrints? coverPrints;

  @override
  State<LibraryHealthScreen> createState() => _LibraryHealthScreenState();
}

class _LibraryHealthScreenState extends State<LibraryHealthScreen> {
  CoverReport? _covers;
  (int, int)? _coverProgress;
  bool _stopCovers = false;

  void _open(Book book) {
    Navigator.of(context).pop();
    widget.onOpenBook(book);
  }

  Future<void> _convertIsbns(List<Book> books) async {
    var changed = 0;
    for (final book in books) {
      final isbn13 = isbn10To13(book.isbn ?? '');
      if (isbn13 == null) continue;
      await widget.repository.setIsbn(book.id, isbn13);
      changed++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Changed $changed ${changed == 1 ? 'ISBN' : 'ISBNs'} to ISBN-13.'),
    ));
  }

  Future<void> _checkCovers() async {
    setState(() {
      _covers = null;
      _coverProgress = (0, 0);
      _stopCovers = false;
    });
    var prints = widget.coverPrints;
    if (prints == null) {
      final dir = await getApplicationSupportDirectory();
      prints = await CoverPrints.load(File(p.join(dir.path, 'cover_prints.json')));
    }
    final report = await checkCovers(
      widget.repository.books,
      prints: prints,
      onProgress: (done, total) {
        if (mounted) setState(() => _coverProgress = (done, total));
      },
      cancelled: () => _stopCovers || !mounted,
    );
    if (!mounted) return;
    setState(() {
      _covers = report;
      _coverProgress = null;
    });
  }

  Widget _bookTile(Book book, {String? detail}) => ListTile(
        dense: true,
        title: Text(book.title),
        subtitle: Text([
          if (book.author.isNotEmpty) book.author,
          book.shelf.label,
          ?detail,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(book),
      );

  Widget _group({
    required IconData icon,
    required String title,
    required String hint,
    required List<Widget> children,
    int? count,
    Widget? action,
  }) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(count == null ? title : '$title ($count)'),
        subtitle: Text(hint),
        children: [
          ?action,
          ...children,
        ],
      ),
    );
  }

  List<Widget> _stalledSection() {
    final stalled = stalledBooks(
      widget.repository.books,
      ebooks: EbookReading.library?.links ?? const {},
      snoozed: widget.settings.stalledSnoozed,
    );
    if (stalled.isEmpty) return const [];
    return [
      _group(
        icon: Icons.hourglass_bottom,
        title: 'Stalled on In progress',
        hint: 'Books you have not touched for much longer than usual.',
        count: stalled.length,
        children: [
          for (final s in stalled)
            ListTile(
              dense: true,
              title: Text(s.book.title),
              subtitle: Text(s.describe()),
              onTap: () => _open(s.book),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => widget.settings
                        .snoozeStalled(s.book.id, DateTime.now()),
                    child: const Text('Keep'),
                  ),
                  TextButton(
                    onPressed: () =>
                        widget.repository.moveTo(s.book.id, Shelf.forLater),
                    child: const Text('For later'),
                  ),
                  TextButton(
                    onPressed: () =>
                        widget.repository.moveTo(s.book.id, Shelf.unfinished),
                    child: const Text('Unfinished'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _coverSection() {
    final progress = _coverProgress;
    final report = _covers;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.image_search_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Check covers',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text(
                          'Finds different books with the same cover, and '
                          'covers that are tiny, blank or the wrong shape. '
                          'Covers from the web are downloaded once.',
                        ),
                      ],
                    ),
                  ),
                  if (progress == null)
                    FilledButton.tonal(
                      onPressed: _checkCovers,
                      child: Text(report == null ? 'Check' : 'Check again'),
                    )
                  else
                    TextButton(
                      onPressed: () => setState(() => _stopCovers = true),
                      child: const Text('Stop'),
                    ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress.$2 == 0 ? null : progress.$1 / progress.$2,
                ),
                Text('${progress.$1} of ${progress.$2}'),
              ],
              if (report != null) ...[
                const SizedBox(height: 8),
                if (report.sameCover.isEmpty &&
                    report.problems.isEmpty &&
                    report.unreadable.isEmpty)
                  const Text('All covers look fine.'),
                for (final group in report.sameCover) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Same cover on ${group.length} books',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  for (final book in group) _bookTile(book),
                ],
                if (report.problems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Covers that look wrong',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                for (final (book, problem) in report.problems)
                  _bookTile(book, detail: problem),
                if (report.unreadable.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Covers that couldn't be loaded (${report.unreadable.length})",
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                for (final book in report.unreadable) _bookTile(book),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library health')),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.settings]),
        builder: (context, _) {
          final issues = checkLibrary(widget.repository.books);
          final exact = widget.repository.findDuplicates().length;
          final possible = findPossibleDuplicates(
            widget.repository.books,
            dismissed: widget.settings.notDuplicates,
          ).length;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (issues.isEmpty && exact + possible == 0)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nothing wrong found in your book details.'),
                ),
              if (exact + possible > 0)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.content_copy_outlined),
                    title: Text(
                      '${exact + possible} possible '
                      '${exact + possible == 1 ? 'duplicate' : 'duplicates'}',
                    ),
                    subtitle: const Text('Open Duplicates to merge them.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DuplicatesScreen(
                          repository: widget.repository,
                          settings: widget.settings,
                        ),
                      ),
                    ),
                  ),
                ),
              ..._stalledSection(),
              for (final entry in issues.entries)
                _group(
                  icon: Icons.report_outlined,
                  title: entry.key.title,
                  hint: entry.key.hint,
                  count: entry.value.length,
                  action: entry.key == HealthIssueKind.oldIsbn
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.tonal(
                              onPressed: () => _convertIsbns(entry.value),
                              child: const Text('Change all to ISBN-13'),
                            ),
                          ),
                        )
                      : null,
                  children: [
                    for (final book in entry.value.take(200))
                      _bookTile(
                        book,
                        detail: entry.key == HealthIssueKind.badIsbn ||
                                entry.key == HealthIssueKind.oldIsbn
                            ? 'ISBN ${book.isbn}'
                            : null,
                      ),
                  ],
                ),
              ..._coverSection(),
            ],
          );
        },
      ),
    );
  }
}
