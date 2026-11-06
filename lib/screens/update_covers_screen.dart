import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/cover_update.dart';
import '../data/open_library_client.dart';
import '../widgets/book_cover.dart';

// The same file is in the Android app; keep the two copies alike.

/// Finds books with no cover, or with an Open Library cover that no longer
/// exists, and fetches the cover Open Library has for them. You see the
/// covers it found and choose which to use. A cover that still loads is never
/// replaced; to change one of those, use Find cover in the book editor.
class UpdateCoversScreen extends StatefulWidget {
  const UpdateCoversScreen({
    super.key,
    required this.repository,
    required this.client,
  });

  final BookRepository repository;
  final OpenLibraryClient client;

  @override
  State<UpdateCoversScreen> createState() => _UpdateCoversScreenState();
}

class _UpdateCoversScreenState extends State<UpdateCoversScreen> {
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;
  CoverScanResult? _result;
  final List<CoverFix> _fixes = [];
  final Set<String> _chosen = {};

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  Future<void> _scan() async {
    final books = coverCandidates(widget.repository.allBooks);
    setState(() {
      _running = true;
      _cancel = false;
      _done = 0;
      _total = books.length;
      _result = null;
      _fixes.clear();
      _chosen.clear();
    });
    final result = await scanCovers(
      books,
      widget.client,
      cancelled: () => _cancel,
      onProgress: (done, total) {
        if (mounted) setState(() => _done = done);
      },
      onFix: (fix) {
        if (!mounted) return;
        setState(() {
          _fixes.add(fix);
          _chosen.add(fix.book.id);
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  Future<void> _apply() async {
    final covers = {
      for (final fix in _fixes)
        if (_chosen.contains(fix.book.id)) fix.book.id: fix.newUrl,
    };
    await widget.repository.setCoversFor(covers);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Updated ${covers.length} ${covers.length == 1 ? 'cover' : 'covers'}.',
        ),
      ),
    );
    setState(() {
      _fixes.removeWhere((fix) => covers.containsKey(fix.book.id));
      _chosen.clear();
    });
  }

  String _summary(CoverScanResult result) {
    final parts = <String>[
      'Looked at ${result.checked} ${result.checked == 1 ? 'book' : 'books'}.',
      if (result.fixes.isEmpty)
        'No covers to update.'
      else
        'Found ${result.fixes.length} '
            '${result.fixes.length == 1 ? 'cover' : 'covers'}.',
      if (result.noMatch > 0)
        '${result.noMatch} need a cover but have no clear match on Open '
            'Library: use Find cover in the book editor for those.',
      if (result.unreachable)
        'Open Library could not be reached. Check your connection and try '
            'again.',
      if (result.stopped) 'Stopped before every book was looked at.',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final candidates = coverCandidates(widget.repository.allBooks).length;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Update covers')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Text(
              'Looks for books with no cover, or whose Open Library cover no '
              'longer exists, and finds the cover Open Library has now. '
              'Covers that still show are left alone, and so are pictures you '
              'added yourself. $candidates '
              '${candidates == 1 ? 'book has' : 'books have'} no cover or an '
              'Open Library cover.',
              style: textTheme.bodyMedium
                  ?.copyWith(color: colours.onSurfaceVariant),
            ),
          ),
          if (_running) ...[
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text('Looked at $_done of $_total books')),
                  TextButton(
                    onPressed: () => setState(() => _cancel = true),
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: candidates == 0 ? null : _scan,
                icon: const Icon(Icons.image_search_outlined),
                label: Text(result == null ? 'Check covers' : 'Check again'),
              ),
            ),
          if (result != null && !_running)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_summary(result), style: textTheme.bodyMedium),
            ),
          for (final fix in _fixes)
            _FixCard(
              key: ValueKey(fix.book.id),
              fix: fix,
              chosen: _chosen.contains(fix.book.id),
              onChanged: (value) => setState(() {
                if (value) {
                  _chosen.add(fix.book.id);
                } else {
                  _chosen.remove(fix.book.id);
                }
              }),
            ),
          if (_fixes.isNotEmpty && !_running)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                onPressed: _chosen.isEmpty ? null : _apply,
                child: Text(
                  'Use ${_chosen.length} '
                  '${_chosen.length == 1 ? 'cover' : 'covers'}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FixCard extends StatelessWidget {
  const _FixCard({
    super.key,
    required this.fix,
    required this.chosen,
    required this.onChanged,
  });

  final CoverFix fix;
  final bool chosen;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final book = fix.book;
    final textTheme = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!chosen),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Checkbox(value: chosen, onChanged: (v) => onChanged(v ?? false)),
              BookCover(
                coverUrl: book.coverUrl,
                width: 40,
                height: 60,
                title: book.title,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 18),
              ),
              BookCover(coverUrl: fix.newUrl, width: 40, height: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    if (book.author.isNotEmpty)
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: colours.onSurfaceVariant),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      fix.problem == CoverProblem.missing
                          ? 'No cover yet'
                          : 'The current cover no longer exists',
                      style: textTheme.labelMedium
                          ?.copyWith(color: colours.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
