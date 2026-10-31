import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/file_match.dart';
import '../data/library_scan.dart';
import 'add_file_flow.dart';

// Windows app only.

/// The files a folder scan was not sure about. For each one you can link it
/// to the likely book, pick another book (or add a new one), or skip it.
class ScanReviewScreen extends StatelessWidget {
  const ScanReviewScreen({
    super.key,
    required this.scanner,
    required this.repository,
  });

  final LibraryScanner scanner;
  final BookRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final pending = scanner.pending;
        final likely = [for (final d in pending) if (d.matches.isNotEmpty) d];
        final unknown = [for (final d in pending) if (d.matches.isEmpty) d];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Files to check'),
            actions: [
              if (pending.isNotEmpty)
                TextButton(
                  onPressed: scanner.skipAll,
                  child: const Text('Skip all'),
                ),
            ],
          ),
          body: pending.isEmpty
              ? const Center(child: Text('Nothing left to check.'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (likely.isNotEmpty) ...[
                      const _Header('Might match a book in your library'),
                      for (final d in likely)
                        _Row(
                          key: ValueKey(d.item.key),
                          decision: d,
                          scanner: scanner,
                          repository: repository,
                        ),
                    ],
                    if (unknown.isNotEmpty) ...[
                      const _Header('Not in your library'),
                      for (final d in unknown)
                        _Row(
                          key: ValueKey(d.item.key),
                          decision: d,
                          scanner: scanner,
                          repository: repository,
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.decision,
    required this.scanner,
    required this.repository,
  });

  final ScanDecision decision;
  final LibraryScanner scanner;
  final BookRepository repository;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _busy = false;

  ScanItem get _item => widget.decision.item;

  Future<void> _run(Future<String?> Function() work) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final problem = await work();
    if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _choose() async {
    final scanner = widget.scanner;
    final books = widget.repository.books;
    final found = FoundBookInfo(title: _item.title, author: _item.author);
    final guess = found.isEmpty ? guessFromFileName(_item.name) : found;
    final choice = await showDialog<LinkChoice>(
      context: context,
      builder: (_) => LinkFileDialog(
        fileName: _item.name,
        found: found,
        books: books,
        matches: widget.decision.matches,
        newBook: guess,
        audio: _item.kind == ScanKind.audiobook,
        hasFile: (id) => scanner.hasLink(_item.kind, id),
      ),
    );
    if (choice == null || !mounted) return;
    await _run(() => choice.bookId != null
        ? scanner.resolveWithBook(_item, choice.bookId!)
        : scanner.resolveWithNewBook(
            _item,
            title: choice.title,
            author: choice.author,
            shelf: choice.shelf,
          ));
  }

  @override
  Widget build(BuildContext context) {
    final best = widget.decision.matches.firstOrNull?.book;
    final audio = _item.kind == ScanKind.audiobook;
    final detail = [
      if (_item.title.isNotEmpty) _item.title,
      if (_item.author.isNotEmpty) _item.author,
    ].join(' · ');
    return ListTile(
      leading: Icon(audio ? Icons.headphones : Icons.menu_book_outlined),
      title: Text(_item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (detail.isNotEmpty) detail,
          if (audio && _item.files.length > 1) '${_item.files.length} files',
        ].join('\n'),
      ),
      isThreeLine: detail.isNotEmpty && audio && _item.files.length > 1,
      trailing: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (best != null)
                  FilledButton.tonal(
                    onPressed: () => _run(
                      () => widget.scanner.resolveWithBook(_item, best.id),
                    ),
                    child: Text(
                      'Link to “${best.title.length > 28 ? '${best.title.substring(0, 27)}…' : best.title}”',
                    ),
                  ),
                OutlinedButton(
                  onPressed: _choose,
                  child: Text(best == null ? 'Choose or add…' : 'Choose book…'),
                ),
                TextButton(
                  onPressed: () => widget.scanner.skip(_item),
                  child: const Text('Skip'),
                ),
              ],
            ),
    );
  }
}
