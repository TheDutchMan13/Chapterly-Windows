import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../server/book_server.dart';
import '../server/new_server_books.dart';
import '../server/server_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// "New on your book server": the books the server found in its folders
/// since you last looked (it checks them every hour). Nothing shows when
/// there are none, or no book server is connected.
class NewServerBooksBanner extends StatefulWidget {
  const NewServerBooksBanner({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<NewServerBooksBanner> createState() => _NewServerBooksBannerState();
}

class _NewServerBooksBannerState extends State<NewServerBooksBanner> {
  // Kept between screens, so the library doesn't ask the server every time
  // it is built.
  static List<ServerBook> _found = const [];
  static DateTime? _newest;
  static DateTime? _checkedAt;
  static const _every = Duration(minutes: 10);

  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    final state = BookServer.sync?.state;
    _wasConnected = state?.connected ?? false;
    state?.addListener(_serverChanged);
    _check();
  }

  @override
  void dispose() {
    BookServer.sync?.state.removeListener(_serverChanged);
    super.dispose();
  }

  void _serverChanged() {
    final connected = BookServer.sync?.state.connected ?? false;
    if (connected && !_wasConnected) _check(force: true);
    if (!connected && _found.isNotEmpty && mounted) {
      setState(() => _found = const []);
    }
    _wasConnected = connected;
  }

  Future<void> _check({bool force = false}) async {
    final sync = BookServer.sync;
    final client = sync?.client;
    if (sync == null || client == null || !sync.state.connected) return;
    final last = _checkedAt;
    if (!force && last != null && DateTime.now().difference(last) < _every) {
      return;
    }
    _checkedAt = DateTime.now();
    try {
      final page = await client.books(sort: 'recent', limit: 30);
      final result = pickNewServerBooks(
        page.books,
        seenAt: widget.settings.serverSeenAt,
        isLinked: (id) => sync.state.bookIdFor(id) != null,
      );
      if (widget.settings.serverSeenAt == null && result.newest != null) {
        widget.settings.setServerSeenAt(result.newest!);
      }
      _newest = result.newest;
      if (mounted) setState(() => _found = result.books);
    } catch (_) {
      // The server is away: try again next time.
      _checkedAt = null;
    }
  }

  void _dismiss() {
    final newest = _newest;
    if (newest != null) widget.settings.setServerSeenAt(newest);
    setState(() => _found = const []);
  }

  Future<void> _showAll() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewBooksSheet(books: _found),
    );
    // The ones added to the library are no longer new.
    final state = BookServer.sync?.state;
    if (state != null && mounted) {
      setState(() => _found = [
            for (final book in _found)
              if (state.bookIdFor(book.id) == null) book,
          ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_found.isEmpty) return const SizedBox.shrink();
    final colours = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final count = _found.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: colours.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Badge.count(
                  count: count,
                  backgroundColor: colours.primary,
                  textColor: colours.onPrimary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'New on your book server',
                    style: textTheme.titleSmall?.copyWith(
                      color: colours.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                for (final book in _found.take(3)) book.title,
                if (count > 3) 'and ${count - 3} more',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium
                  ?.copyWith(color: colours.onPrimaryContainer),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: _showAll,
                  child: Text(count == 1 ? 'See the new book' : 'See new books'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _dismiss, child: const Text('Dismiss')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The new books, each with a button to get it.
class _NewBooksSheet extends StatefulWidget {
  const _NewBooksSheet({required this.books});

  final List<ServerBook> books;

  @override
  State<_NewBooksSheet> createState() => _NewBooksSheetState();
}

class _NewBooksSheetState extends State<_NewBooksSheet> {
  final _busy = <String>{};
  final _done = <String>{};

  Future<void> _get(ServerBook book) async {
    final downloads = BookServer.downloads;
    if (downloads == null) return;
    setState(() => _busy.add(book.id));
    final result = await downloads.download(book);
    if (!mounted) return;
    setState(() {
      _busy.remove(book.id);
      if (result.problem == null) _done.add(book.id);
    });
    final problem = result.problem;
    if (problem != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('New on your book server', style: textTheme.titleLarge),
            ),
            for (final book in widget.books)
              ListTile(
                leading: Icon(book.isAudiobook
                    ? Icons.headphones_outlined
                    : Icons.menu_book_outlined),
                title: Text(book.title),
                subtitle: Text([
                  if (book.author.isNotEmpty) book.author,
                  book.isAudiobook ? 'Audiobook' : book.format.toUpperCase(),
                ].join(' · ')),
                trailing: _done.contains(book.id)
                    ? const Icon(Icons.check_circle)
                    : _busy.contains(book.id)
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : FilledButton.tonal(
                            onPressed: () => _get(book),
                            child: const Text('Download'),
                          ),
              ),
          ],
        ),
      ),
    );
  }
}
