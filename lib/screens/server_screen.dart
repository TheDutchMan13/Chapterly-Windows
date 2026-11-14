import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/server_code.dart';
import '../ebook/ebook_library.dart' show formatFileSize;
import '../server/book_server.dart';
import '../server/server_client.dart';
import '../server/server_downloads.dart';
import '../server/server_sync.dart';
import 'book_detail_screen.dart';
import 'server_devices_screen.dart';

// The same screen is in the Android app.

/// "11 h 2 min".
String formatListenLength(int ms) {
  final minutes = ms ~/ 60000;
  final hours = minutes ~/ 60;
  return hours == 0 ? '$minutes min' : '$hours h ${minutes % 60} min';
}

/// Files bigger than this ask before downloading.
const _askAbove = 200 * 1024 * 1024;

/// Your own book server: connect once, then browse and search your library
/// there and download books into Chapterly. Your place in those books
/// syncs with your other devices.
class ServerScreen extends StatelessWidget {
  const ServerScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
    required this.sync,
    required this.downloads,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;
  final ServerSync sync;
  final ServerDownloads downloads;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync.state,
      builder: (context, _) => sync.state.connected
          ? _BrowseView(
              key: ValueKey(sync.state.address),
              repository: repository,
              settings: settings,
              fileIo: fileIo,
              sync: sync,
              downloads: downloads,
            )
          : _ConnectView(sync: sync),
    );
  }
}

// ---- Connecting ----

class _ConnectView extends StatefulWidget {
  const _ConnectView({required this.sync});

  final ServerSync sync;

  @override
  State<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<_ConnectView> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  bool _showToken = false;
  bool _busy = false;
  String? _problem;
  String? _note;

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final address = parseServerAddress(_address.text);
    final token = _token.text.trim();
    if (address == null) {
      setState(() => _problem =
          'Type the server\'s address, such as 100.101.102.103:8780.');
      return;
    }
    if (token.isEmpty) {
      setState(() => _problem = 'Paste the token the server gave you.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _note = null;
    });
    final client = widget.sync.clientFor(address, token);
    try {
      await client.ping();
      final name = await client.me();
      await widget.sync.state.connect(address, token, name);
      unawaited(widget.sync.syncNow());
    } on ServerFailure catch (failure) {
      if (mounted) setState(() => _problem = failure.message);
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) controller.text = text;
  }

  /// Fills both fields from a server code. Does not connect.
  bool _fillFromCode(String text) {
    final code = parseServerCode(text);
    if (code == null) return false;
    _address.text = code.address;
    _token.text = code.token;
    setState(() {
      _problem = null;
      _note = 'Code read. Press Connect.';
    });
    return true;
  }

  Future<void> _pasteCode() async {
    final messenger = ScaffoldMessenger.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (!_fillFromCode(data?.text ?? '')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That is not a Chapterly server code')),
      );
    }
  }

  /// A whole server code pasted into the Address field fills both fields.
  void _addressChanged(String text) {
    if (text.trimLeft().startsWith('chapterly-server:')) _fillFromCode(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Connect to your own Chapterly book server to browse your '
            'library there, download books into Chapterly and keep your '
            'place in sync with your other devices.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pasteCode,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste server code'),
            ),
          ),
          if (_note case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(note),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: _addressChanged,
            decoration: InputDecoration(
              labelText: 'Address',
              hintText: '100.101.102.103:8780',
              helperText: 'Its Tailscale address and port',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () => _paste(_address),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: !_showToken,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Token',
              helperText: 'From "add-user" on the server',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _showToken ? 'Hide token' : 'Show token',
                    icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _showToken = !_showToken),
                  ),
                  IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () => _paste(_token),
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => _busy ? null : _connect(),
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                problem,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Connect'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tailscale must be on. The token is kept on this device only.',
          ),
        ],
      ),
    );
  }
}

// ---- Browsing ----

enum _Kind { all, ebook, audiobook }

class _BrowseView extends StatefulWidget {
  const _BrowseView({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
    required this.sync,
    required this.downloads,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;
  final ServerSync sync;
  final ServerDownloads downloads;

  @override
  State<_BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<_BrowseView> {
  static const _pageSize = 50;

  final _query = TextEditingController();
  final _books = <ServerBook>[];
  _Kind _kind = _Kind.all;
  int _total = 0;
  bool _loading = false;
  String? _problem;
  Timer? _typing;

  /// Answers to an older search are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _typing?.cancel();
    _query.dispose();
    super.dispose();
  }

  ServerClient? get _client => widget.sync.client;

  void _reload() {
    _generation++;
    _books.clear();
    _total = 0;
    _problem = null;
    _loading = false;
    _loadMore();
  }

  Future<void> _loadMore() async {
    final client = _client;
    if (client == null || _loading) return;
    if (_books.isNotEmpty && _books.length >= _total) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await client.books(
        query: _query.text,
        kind: _kind == _Kind.all ? null : _kind.name,
        offset: _books.length,
        limit: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _books.addAll(page.books);
        _total = page.total;
        _problem = null;
      });
    } on ServerFailure catch (failure) {
      if (mounted && generation == _generation) {
        setState(() => _problem = failure.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _typed(String _) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(_reload);
    });
  }

  void _openBook(String bookId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookDetailScreen(
        repository: widget.repository,
        settings: widget.settings,
        fileIo: widget.fileIo,
        bookId: bookId,
      ),
    ));
  }

  Future<void> _download(ServerBook book) async {
    final messenger = ScaffoldMessenger.of(context);
    if (book.size > _askAbove) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Download ${formatFileSize(book.size)}?'),
          content: Text('"${book.title}" is a big file.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    final result = await widget.downloads.download(book);
    if (!mounted) return;
    final bookId = result.bookId;
    final text = result.problem ??
        (result.matchedExisting
            ? '"${book.title}" was already in your library. Your place in '
                'it now syncs.'
            : '"${book.title}" is in your library');
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      action: bookId == null
          ? null
          : SnackBarAction(label: 'Open', onPressed: () => _openBook(bookId)),
    ));
  }

  Future<void> _sendToOthers(ServerBook book) async {
    final messenger = ScaffoldMessenger.of(context);
    final problem = await widget.downloads.sendToOthers(book);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        problem ??
            '"${book.title}" will download on your other devices when they '
                'next open Chapterly',
      ),
    ));
  }

  /// Deletes the book's file from this device after asking. The book, and
  /// your place in it, stay in your library.
  Future<void> _removeDownload(String bookId, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final item = await widget.downloads.downloadedBook(bookId);
    if (!mounted) return;
    if (item == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('"$title" has no file on this device.')),
      );
      return;
    }
    if (!await confirmRemoveDownload(context, item) || !mounted) return;
    await widget.downloads.removeFile(item);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(content: Text('Removed the file of "$title".')),
    );
  }

  void _openDevices() {
    final client = _client;
    if (client == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServerDevicesScreen(client: client),
    ));
  }

  void _openDownloads() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DownloadsScreen(downloads: widget.downloads),
    ));
  }

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    String? text;
    if (BookServer.sync == widget.sync) {
      text = await BookServer.syncAll();
    } else {
      final moved = await widget.sync.syncNow();
      if (moved > 0) text = 'Moved on in $moved ${moved == 1 ? 'book' : 'books'}';
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(widget.sync.problem ?? text ?? 'Everything is up to date'),
    ));
    setState(() {});
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Disconnect from the server?'),
        content: const Text(
          'Books you downloaded stay in your library, but your place in them '
          'stops syncing. To connect again you need the token.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (sure == true) await widget.sync.state.disconnect();
  }

  String _details(ServerBook book) {
    final parts = <String>[
      if (book.series case final series?)
        book.seriesIndex == null
            ? series
            : '$series #${_number(book.seriesIndex!)}',
      if (book.isAudiobook)
        book.durationMs == null
            ? 'Audiobook'
            : 'Audiobook, ${formatListenLength(book.durationMs!)}'
      else
        '${book.format.toUpperCase()}, ${formatFileSize(book.size)}',
      if (book.progress case final progress? when progress.fraction > 0)
        '${(progress.fraction * 100).round()}% read',
    ];
    return parts.join(' · ');
  }

  static String _ago(DateTime at) {
    final gap = DateTime.now().difference(at);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    if (gap.inHours < 24) return '${gap.inHours} h ago';
    return '${gap.inDays} d ago';
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  Widget _cover(ServerBook book) {
    final client = _client;
    const placeholder = SizedBox(
      width: 40,
      height: 56,
      child: Icon(Icons.menu_book_outlined),
    );
    if (!book.hasCover || client == null) {
      return book.isAudiobook
          ? const SizedBox(
              width: 40,
              height: 56,
              child: Icon(Icons.headphones_outlined),
            )
          : placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        client.coverUri(book.id).toString(),
        headers: client.authHeaders,
        width: 40,
        height: 56,
        fit: BoxFit.cover,
        cacheWidth: 120,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }

  Widget _action(ServerBook book) {
    final downloads = widget.downloads;
    if (downloads.isDownloading(book.id)) {
      return SizedBox(
        width: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              value: downloads.progressOf(book.id),
            ),
          ),
        ),
      );
    }
    final local = downloads.localBookFor(book);
    if (local != null) {
      return IconButton(
        tooltip: 'In your library',
        icon: Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
        ),
        onPressed: () => _openBook(local),
      );
    }
    if (!downloads.canOpen(book)) {
      return const IconButton(
        tooltip: 'Chapterly cannot open this kind of file',
        icon: Icon(Icons.block),
        onPressed: null,
      );
    }
    return IconButton(
      tooltip: 'Download',
      icon: const Icon(Icons.download_outlined),
      onPressed: () => _download(book),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.sync.state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book server'),
        actions: [
          ListenableBuilder(
            listenable: widget.sync,
            builder: (context, _) => IconButton(
              tooltip: 'Sync your places now',
              icon: widget.sync.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              onPressed: widget.sync.busy ? null : _syncNow,
            ),
          ),
          IconButton(
            tooltip: 'Downloads',
            icon: const Icon(Icons.download_done_outlined),
            onPressed: _openDownloads,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'disconnect') _disconnect();
              if (value == 'devices') _openDevices();
              if (value == 'library') {
                state.setLibrarySync(!state.librarySync);
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'library',
                checked: state.librarySync,
                child: const Text('Sync my whole library'),
              ),
              const PopupMenuItem(value: 'devices', child: Text('Devices on the server')),
              const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _query,
              onChanged: _typed,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search the server',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _query.clear();
                          setState(_reload);
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<_Kind>(
              segments: const [
                ButtonSegment(value: _Kind.all, label: Text('All')),
                ButtonSegment(value: _Kind.ebook, label: Text('Ebooks')),
                ButtonSegment(value: _Kind.audiobook, label: Text('Audiobooks')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() {
                _kind = value.first;
                _reload();
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (_total > 0 || !_loading)
                    '$_total ${_total == 1 ? 'book' : 'books'}',
                  if (state.name case final name?) 'signed in as $name',
                  if (state.librarySync && state.librarySyncedAt != null)
                    'library synced ${_ago(state.librarySyncedAt!)}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (_problem case final problem?)
            MaterialBanner(
              content: Text(problem),
              actions: [
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Try again'),
                ),
              ],
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.downloads, state]),
              builder: (context, _) {
                if (_books.isEmpty) {
                  return Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : _problem != null
                            ? const SizedBox.shrink()
                            : Text(
                                _query.text.isEmpty
                                    ? 'No books on the server yet.'
                                    : 'No books match.',
                              ),
                  );
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 600 &&
                        _problem == null) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    itemCount: _books.length + (_books.length < _total ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _books.length) {
                        // After a failed page, wait to be asked again
                        // rather than try over and over.
                        if (_problem != null) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() => _problem = null);
                                  _loadMore();
                                },
                                child: const Text('Load more'),
                              ),
                            ),
                          );
                        }
                        if (!_loading) {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => _loadMore());
                        }
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final book = _books[index];
                      final local = widget.downloads.localBookFor(book);
                      return ListTile(
                        leading: _cover(book),
                        title: Text(book.title),
                        subtitle: Text(
                          [
                            if (book.author.isNotEmpty) book.author,
                            _details(book),
                          ].join('\n'),
                        ),
                        isThreeLine: book.author.isNotEmpty,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _action(book),
                            PopupMenuButton<String>(
                              tooltip: 'More',
                              onSelected: (value) {
                                if (value == 'send') _sendToOthers(book);
                                if (value == 'remove' && local != null) {
                                  _removeDownload(local, book.title);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'send',
                                  child: Text('Send to my other devices'),
                                ),
                                if (local != null)
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remove download (keep the book)'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        onTap: local != null
                            ? () => _openBook(local)
                            : widget.downloads.canOpen(book) &&
                                    !widget.downloads.isDownloading(book.id)
                                ? () => _download(book)
                                : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Downloads ----

/// Asks before deleting a downloaded book's file. True to go ahead.
Future<bool> confirmRemoveDownload(
  BuildContext context,
  DownloadedBook item,
) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Remove the file of "${item.title}"?'),
      content: Text(
        'This frees ${formatFileSize(item.bytes)}. The book stays in your '
        'library with your place in it, and you can download it again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return sure == true;
}

/// Books from the server on this device and the space they take. Removing
/// a file keeps the book in your library; download it again any time.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.downloads});

  final ServerDownloads downloads;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<DownloadedBook>> _items = widget.downloads.downloaded();

  void _refresh() => setState(() => _items = widget.downloads.downloaded());

  Future<void> _removeAll(List<DownloadedBook> items, int total) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: Text(
          'This deletes the files of ${items.length} '
          '${items.length == 1 ? 'book' : 'books'} and frees '
          '${formatFileSize(total)}. The books stay in your library with '
          'your places in them, and you can download them again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.downloads.removeAll();
    if (mounted) _refresh();
  }

  Future<void> _remove(DownloadedBook item) async {
    if (!await confirmRemoveDownload(context, item)) return;
    await widget.downloads.removeFile(item);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: FutureBuilder<List<DownloadedBook>>(
        future: _items,
        builder: (context, snapshot) {
          final items = snapshot.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const Center(child: Text('No books from the server on this device.'));
          }
          final total = items.fold<int>(0, (sum, i) => sum + i.bytes);
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${items.length} ${items.length == 1 ? 'book uses' : 'books use'} '
                        '${formatFileSize(total)} on this device',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _removeAll(items, total),
                      child: const Text('Remove all'),
                    ),
                  ],
                ),
              ),
              for (final item in items)
                ListTile(
                  leading: Icon(item.isAudiobook
                      ? Icons.headphones_outlined
                      : Icons.menu_book_outlined),
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.isAudiobook ? 'Audiobook' : 'Ebook'} · '
                    '${formatFileSize(item.bytes)}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove the file (the book stays)',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(item),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
