import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/auto_tag.dart';
import '../data/book_repository.dart';
import '../data/open_library_client.dart';
import '../data/wikidata_client.dart';
import '../models/book.dart';

// Windows app only.

/// Finds tags for the books that have none, from Open Library. Nothing is
/// added until you have looked at the list. It can also be tried on books
/// you tagged yourself, to see how well it works.
class AutoTagScreen extends StatefulWidget {
  const AutoTagScreen({
    super.key,
    required this.repository,
    required this.settings,
    this.client,
    this.wikidata,
  });

  final BookRepository repository;
  final AppSettings settings;

  /// For tests; the real Open Library otherwise.
  final OpenLibraryClient? client;

  /// For tests; the real Wikidata otherwise.
  final WikidataClient? wikidata;

  @override
  State<AutoTagScreen> createState() => _AutoTagScreenState();
}

enum _Stage { start, running, review }

class _AutoTagScreenState extends State<AutoTagScreen> {
  late final OpenLibraryClient _client = widget.client ?? OpenLibraryClient();
  late final WikidataClient _wikidata = widget.wikidata ?? WikidataClient();
  _Stage _stage = _Stage.start;
  bool _testing = false;
  bool _stop = false;
  int _done = 0;
  int _total = 0;
  String _current = '';
  List<TagPlan>? _plans;
  TagTestReport? _report;

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  List<Book> get _untagged => [
        for (final book in widget.repository.books)
          if (book.tags.isEmpty) book,
      ];

  /// Open Library asked to slow down during this run: it is not asked again
  /// until the next one.
  bool _openLibraryBusy = false;

  /// Open Library, a little apart, so a big library does not flood it, and
  /// Wikidata when switched on, even when Open Library could not be asked.
  Future<List<String>> _subjects(Book book) async {
    List<String>? subjects;
    if (!_openLibraryBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        subjects = await _client.subjectsFor(
          title: book.title,
          author: book.author,
          isbn: book.isbn,
        );
      } on OpenLibraryException catch (error) {
        if (error.busy) _openLibraryBusy = true;
      } catch (_) {
        // Could not be reached; Wikidata may still know.
      }
    }
    final genres = widget.settings.useWikidata
        ? await _wikidata.genresFor(title: book.title, author: book.author)
        : const <String>[];
    if (subjects == null) {
      throw OpenLibraryUnavailable(found: genres, busy: _openLibraryBusy);
    }
    return mergeSubjects(subjects, genres);
  }

  Future<void> _find() async {
    final books = _untagged;
    if (books.isEmpty) return;
    setState(() {
      _stage = _Stage.running;
      _openLibraryBusy = false;
      _testing = false;
      _stop = false;
      _done = 0;
      _total = books.length;
      _current = '';
    });
    final plans = await planTags(
      books,
      widget.repository.books,
      subjects: _subjects,
      stopped: () => _stop,
      onProgress: (done, total, book) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
          _current = book?.title ?? '';
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _stage = _Stage.review;
    });
  }

  Future<void> _test() async {
    setState(() {
      _stage = _Stage.running;
      _openLibraryBusy = false;
      _testing = true;
      _stop = false;
      _done = 0;
      _total = pickTestBooks(widget.repository.books).length;
      _current = '';
    });
    final report = await runTagTest(
      widget.repository.books,
      subjects: _subjects,
      stopped: () => _stop,
      onProgress: (done, total) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _stage = _Stage.start;
    });
  }

  Future<void> _apply() async {
    final plans = _plans ?? const <TagPlan>[];
    final tagsByBook = {
      for (final plan in plans)
        if (plan.checkedTags.isNotEmpty) plan.book.id: plan.checkedTags,
    };
    if (tagsByBook.isEmpty) return;
    final before = [
      for (final id in tagsByBook.keys) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.addTagsToBooks(tagsByBook);
    if (!mounted) return;
    setState(() {
      _plans = null;
      _stage = _Stage.start;
    });
    final count = tagsByBook.length;
    messenger.showSnackBar(SnackBar(
      content: Text('Added tags to $count book${count == 1 ? '' : 's'}.'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => widget.repository.putBack(before),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tag my library')),
      body: switch (_stage) {
        _Stage.start => _startView(context),
        _Stage.running => _runningView(context),
        _Stage.review => _reviewView(context),
      },
      bottomNavigationBar: _stage == _Stage.review ? _applyBar(context) : null,
    );
  }

  Widget _startView(BuildContext context) {
    final untagged = _untagged.length;
    final tested = pickTestBooks(widget.repository.books).length;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          untagged == 0
              ? 'Every book in your library has tags.'
              : '$untagged book${untagged == 1 ? ' has' : 's have'} no tags.',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Chapterly looks each book up on Open Library and matches its '
          'subjects to your tags (and to the tags on your other books by the '
          'same author or in the same series). Sure matches are ticked; you '
          'check the list before anything is added. Books that already have '
          'tags are not changed.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also use Wikidata'),
          subtitle: const Text(
            'Adds the genres Wikidata lists for a book. Slower, and it sends '
            'each title and author to wikidata.org.',
          ),
          value: widget.settings.useWikidata,
          onChanged: (value) =>
              setState(() => widget.settings.setUseWikidata(value)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                'Find tags for $untagged book${untagged == 1 ? '' : 's'}',
              ),
              onPressed: untagged == 0 ? null : _find,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.science_outlined),
              label: Text(
                'Test on $tested tagged book${tested == 1 ? '' : 's'}',
              ),
              onPressed: tested == 0 ? null : _test,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The test hides the tags of some books you tagged yourself, finds '
          'tags for them, and counts how many of yours came back. Nothing is '
          'changed.',
          style: theme.textTheme.bodySmall,
        ),
        if (_report case final report?) ...[
          const SizedBox(height: 16),
          _ReportCard(report: report),
        ],
      ],
    );
  }

  Widget _runningView(BuildContext context) {
    final progress = _total == 0 ? null : _done / _total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _testing
                    ? 'Testing on your tagged books: $_done of $_total'
                    : 'Looking up $_done of $_total',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(_current, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _stop ? null : () => setState(() => _stop = true),
                child: Text(_stop ? 'Stopping...' : 'Stop'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewView(BuildContext context) {
    final plans = _plans ?? const <TagPlan>[];
    final found = [
      for (final plan in plans)
        if (plan.proposals.isNotEmpty) plan,
    ];
    final empty = [
      for (final plan in plans)
        if (plan.proposals.isEmpty) plan,
    ];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Tap a tag to add or leave it out. Ticked tags are added. New tag '
            'names start unticked.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (_openLibraryBusy)
          const _Notice(text: '$openLibraryBusyNote.'),
        if (widget.settings.useWikidata && _wikidata.tooBusy)
          const _Notice(
            text: 'Wikidata asked Chapterly to slow down, so it was skipped '
                'for the rest of this run.',
          ),
        for (final plan in found)
          _PlanTile(plan: plan, onChanged: () => setState(() {})),
        if (empty.isNotEmpty)
          ExpansionTile(
            title: Text(
              'No tags found for ${empty.length} '
              'book${empty.length == 1 ? '' : 's'}',
            ),
            children: [
              for (final plan in empty)
                ListTile(
                  dense: true,
                  title: Text(plan.book.title),
                  subtitle: Text([
                    if (plan.book.author.isNotEmpty) plan.book.author,
                    ?plan.note,
                  ].join(' · ')),
                ),
            ],
          ),
      ],
    );
  }

  Widget _applyBar(BuildContext context) {
    final plans = _plans ?? const <TagPlan>[];
    final books = plans.where((p) => p.checkedTags.isNotEmpty).length;
    final tags = plans.fold<int>(0, (sum, p) => sum + p.checkedTags.length);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text('$tags tag${tags == 1 ? '' : 's'} on $books '
                  'book${books == 1 ? '' : 's'}'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _plans = null;
                _stage = _Stage.start;
              }),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: books == 0 ? null : _apply,
              child: Text('Add tags to $books book${books == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.onChanged});

  final TagPlan plan;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final book = plan.book;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(book.title, style: Theme.of(context).textTheme.titleSmall),
          if (book.author.isNotEmpty)
            Text(book.author, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in plan.proposals)
                Tooltip(
                  message: p.reason.isEmpty ? 'Open Library' : p.reason,
                  child: FilterChip(
                    label: Text(p.isNew ? '${p.tag} (new)' : p.tag),
                    selected: p.checked,
                    onSelected: (value) {
                      p.checked = value;
                      onChanged();
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final TagTestReport report;

  String _percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final score = report.openLibrary;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Test result', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Found ${score.found} of your ${score.yourTags} tags '
              '(${_percent(score.foundShare)}).',
            ),
            Text(
              '${score.right} of the ${score.suggested} tags it would add were '
              'yours (${_percent(score.rightShare)}).',
            ),
            Text(
              'At least one of your tags on ${score.booksHit} of '
              '${score.books} books; nothing at all on ${score.booksEmpty}.',
            ),
            const SizedBox(height: 6),
            Text(
              'A tag of yours that it missed is not always wrong: it may pick '
              'a different tag of yours that also fits.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line notice at the top of the review.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
