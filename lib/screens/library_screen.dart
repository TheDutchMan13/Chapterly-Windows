import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/book_sorting.dart';
import '../data/collections.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/pc_sync.dart';
import '../data/rating_text.dart';
import '../data/update_check.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../models/wish_priority.dart';
import '../widgets/book_cover.dart';
import 'add_book_dialog.dart';
import 'book_detail_screen.dart';
import 'book_table.dart';
import 'bulk_add_screen.dart';
import 'cover_size_dialog.dart';
import 'duplicates_screen.dart';
import 'file_drop.dart';
import 'manage_shelves_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shelf_picker.dart';
import 'sync_preview.dart';
import 'trash_screen.dart';

enum _AddChoice { search, isbn, bulk, manual }

/// From this width the open book shows beside the list.
const _twoPaneWidth = 900.0;

/// The table needs more room, so it shows the open book beside it only
/// from this width.
const _twoPaneTableWidth = 1300.0;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.settings,
    required this.pcSync,
    required this.fileIo,
    this.onOpenSettings,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;
  final PcSync pcSync;
  final FileIo fileIo;

  /// Shows Settings in the side menu. Without it, Settings opens as a page.
  final VoidCallback? onOpenSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final Set<String> _selectedTags = {};
  final Set<BookFormat> _formats = {};
  final Set<String> _selected = {};
  final _searchController = TextEditingController();
  bool _searching = false;
  bool _favoritesOnly = false;
  final Set<String> _excludedTags = {};
  bool _matchAllTags = true;
  int? _finishYear;

  /// The book shown beside the list in a wide window.
  String? _currentId;

  /// Whether the window is wide enough for two panes (set while laying out).
  bool _wide = false;

  @override
  void initState() {
    super.initState();
    widget.pcSync.onBackgroundSync = _syncedInBackground;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startUp());
  }

  void _syncedInBackground(int changed) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Synced with your phone: $changed '
          '${changed == 1 ? 'book' : 'books'} changed',
        ),
      ),
    );
  }

  /// Syncs with the phone and checks for updates when Chapterly opens. Both
  /// stay quiet unless there is news.
  Future<void> _startUp() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final synced = await widget.pcSync.syncOnOpen();
    final changed = widget.settings.lastSyncChanged;
    if (synced && changed > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Synced with your phone: $changed '
            '${changed == 1 ? 'book' : 'books'} changed',
          ),
        ),
      );
    }
    final update = await checkForUpdateIfDue(widget.settings);
    if (update == null) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: Text('Chapterly ${update.version} is available.'),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () => launchUrl(
            Uri.parse(update.url),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
    );
  }

  /// Esc closes the selection, then the search, then the open book.
  void _escape() {
    if (_selected.isNotEmpty) {
      setState(_selected.clear);
    } else if (_searching) {
      _stopSearching();
    } else if (_currentId != null) {
      setState(() => _currentId = null);
    }
  }

  /// Runs a selection action (trash, add to a shelf) on just [book].
  void _actOn(Book book, Future<void> Function() action) {
    setState(() {
      _selected
        ..clear()
        ..add(book.id);
    });
    action();
  }

  Future<void> _showBookMenu(Book book, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: () => _openBook(book),
          child: const Text('Open'),
        ),
        const PopupMenuDivider(),
        for (final shelf in Shelf.values)
          if (shelf != book.shelf)
            PopupMenuItem(
              value: () => widget.repository.moveTo(book.id, shelf),
              child: Text('Move to ${shelf.label}'),
            ),
        PopupMenuItem(
          value: () => _actOn(book, _addSelectedToShelf),
          child: const Text('Add to one of your shelves...'),
        ),
        PopupMenuItem(
          value: () => widget.repository
              .setFavorite(book.id, favorite: !book.favorite),
          child: Text(
            book.favorite ? 'Remove from favorites' : 'Add to favorites',
          ),
        ),
        PopupMenuItem(
          value: () => setState(() => _selected.add(book.id)),
          child: const Text('Select'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => _actOn(book, _trashSelected),
          child: const Text('Move to trash'),
        ),
      ],
    );
    choice?.call();
  }

  /// The open book in a wide window, or a hint when none is open. The pane
  /// has its own messenger so its messages (such as Undo) show there.
  Widget _detailPane() {
    final id = _currentId;
    final book = id == null ? null : widget.repository.byId(id);
    if (book != null && book.deletedAt == null) {
      return ScaffoldMessenger(
        child: BookDetailScreen(
          key: ValueKey(book.id),
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
          bookId: book.id,
          onClose: () => setState(() => _currentId = null),
        ),
      );
    }
    return ScaffoldMessenger(
      child: Scaffold(
        body: Center(
          child: Text(
            'Pick a book to see it here.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }

  /// Keyboard shortcuts, file dropping and, in a wide window, the open book
  /// beside the list.
  Widget _frame(Widget library) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _searching = true),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _addBook,
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): _addSeveral,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _syncNow,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            _openSettings,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            _resizeCovers(0.1),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            _resizeCovers(-0.1),
      },
      child: Focus(
        autofocus: true,
        child: FileDropTarget(
          repository: widget.repository,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final table = widget.settings.display == DisplayMode.table;
              _wide = width >= (table ? _twoPaneTableWidth : _twoPaneWidth);
              final share = width * (table ? 0.58 : 0.42);
              final least = table ? 700.0 : 380.0;
              final most = table ? 1100.0 : 560.0;
              final listWidth = !_wide
                  ? width
                  : share < least
                      ? least
                      : share > most
                          ? most
                          : share;
              return Row(
                children: [
                  SizedBox(width: listWidth, child: library),
                  if (_wide) const VerticalDivider(width: 1),
                  if (_wide) Expanded(child: _detailPane()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.pcSync.onBackgroundSync == _syncedInBackground) {
      widget.pcSync.onBackgroundSync = null;
    }
    _searchController.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _selectedTags.isNotEmpty ||
      _excludedTags.isNotEmpty ||
      _finishYear != null ||
      _formats.isNotEmpty ||
      _favoritesOnly ||
      _searchController.text.trim().isNotEmpty;

  void _toggleFormat(BookFormat format) {
    setState(() {
      if (!_formats.add(format)) _formats.remove(format);
    });
  }

  void _stopSearching() {
    setState(() {
      _searching = false;
      _searchController.clear();
    });
  }

  void _toggleSelected(Book book) {
    setState(() {
      if (!_selected.add(book.id)) _selected.remove(book.id);
    });
  }

  Future<void> _moveSelected() async {
    final shelf = await showShelfPicker(context);
    if (shelf == null || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids)
        ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.moveAllTo(ids, shelf);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${ids.length} book${ids.length == 1 ? '' : 's'} '
          'to ${shelf.label}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  Future<void> _tagSelected() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tag == null || tag.trim().isEmpty || !mounted) return;
    await widget.repository.addTagToAll({..._selected}, tag);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _trashSelected() async {
    final ids = {..._selected};
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.trashAll(ids);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${ids.length} book${ids.length == 1 ? '' : 's'} moved to the trash',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.restoreAll(ids),
        ),
      ),
    );
  }

  /// Ctrl+= and Ctrl+- make the covers in the grid bigger or smaller.
  void _resizeCovers(double step) {
    if (widget.settings.display != DisplayMode.grid) return;
    widget.settings.setCoverScale(widget.settings.coverScale + step);
  }

  void _openDuplicates() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuplicatesScreen(repository: widget.repository),
      ),
    );
  }

  void _openShelves() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManageShelvesScreen(
          repository: widget.repository,
          settings: widget.settings,
        ),
      ),
    );
  }

  Future<void> _addSelectedToShelf() async {
    final names = allCollectionNames(widget.settings, widget.repository);
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Add to shelf'),
        children: [
          for (final name in names)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(name),
              child: Text(name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('New shelf...'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    var name = choice;
    if (name.isEmpty) {
      final controller = TextEditingController();
      final typed = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New shelf'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Shelf name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (typed == null || typed.trim().isEmpty || !mounted) return;
      name = typed.trim();
      widget.settings.addCollection(name);
    }
    await widget.repository.addToCollectionAll({..._selected}, name);
    if (mounted) setState(_selected.clear);
  }

  void _openTrash() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrashScreen(repository: widget.repository),
      ),
    );
  }

  /// Tapping a tag cycles it: off, shown, hidden, off.
  void _cycleTag(String tag) {
    setState(() {
      if (_selectedTags.remove(tag)) {
        _excludedTags.add(tag);
      } else if (!_excludedTags.remove(tag)) {
        _selectedTags.add(tag);
      }
    });
  }

  Future<void> _chooseFinishYear() async {
    final years = widget.repository.finishedYears;
    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Finished in'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('Any year'),
          ),
          for (final year in years)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(year),
              child: Text('$year'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _finishYear = choice == 0 ? null : choice);
  }

  Future<void> _changeFormatSelected() async {
    final choice = await showDialog<List<BookFormat?>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Change format'),
        children: [
          for (final format in BookFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop([format]),
              child: Text(format.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop([null]),
            child: const Text('Not set'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.setFormatAll(ids, choice.first);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Changed the format of ${ids.length} '
            'book${ids.length == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  Future<void> _setPrioritySelected() async {
    final choice = await showDialog<List<WishPriority?>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Set priority'),
        children: [
          for (final priority in WishPriority.values.reversed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop([priority]),
              child: Text(priority.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop([null]),
            child: const Text('Not set'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.setPriorityAll(ids, choice.first);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Changed the priority of ${ids.length} '
            'book${ids.length == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  Future<void> _changeAuthorSelected() async {
    final controller = TextEditingController();
    final author = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change author'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Author'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (author == null || author.trim().isEmpty || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.setAuthorAll(ids, author);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Changed the author of ${ids.length} '
            'book${ids.length == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  void _openBook(Book book) {
    if (_wide) {
      setState(() => _currentId = book.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
          bookId: book.id,
        ),
      ),
    );
  }

  void _openSettings() {
    final show = widget.onOpenSettings;
    if (show != null) {
      show();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          repository: widget.repository,
          settings: widget.settings,
          pcSync: widget.pcSync,
          fileIo: widget.fileIo,
        ),
      ),
    );
  }

  Future<void> _addBook() async {
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search Open Library'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.search),
            ),
            ListTile(
              leading: const Icon(Icons.numbers),
              title: const Text('Look up an ISBN'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.isbn),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add several at once (Ctrl+Shift+N)'),
              subtitle: const Text('Paste a list of ISBNs or titles'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.bulk),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Add manually'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.manual),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AddChoice.search:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SearchScreen(
              repository: widget.repository,
              client: widget.client,
              settings: widget.settings,
            ),
          ),
        );
      case _AddChoice.isbn:
        await _lookUpIsbn();
      case _AddChoice.bulk:
        await _addSeveral();
      case _AddChoice.manual:
        await _addManually();
    }
  }

  /// Paste a list of books and add them all.
  Future<void> _addSeveral() async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => BulkAddScreen(
          repository: widget.repository,
          client: widget.client,
          settings: widget.settings,
        ),
      ),
    );
    if (added == null || added == 0) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Added $added ${added == 1 ? 'book' : 'books'}')),
    );
  }

  Future<void> _addManually({String? isbn}) async {
    final data = await showAddBookDialog(
      context,
      isbn: isbn,
      initialShelf: widget.settings.defaultShelf ?? Shelf.forLater,
      initialFormat: widget.settings.defaultFormat,
      initialTags: widget.settings.defaultTags,
    );
    if (data == null) return;
    await widget.repository.add(
      title: data.title,
      author: data.author,
      shelf: data.shelf,
      tags: data.tags,
      isbn: data.isbn,
      pages: data.pages,
      format: data.format,
    );
  }

  /// Asks for an ISBN, looks it up on Open Library, and adds the book.
  Future<void> _lookUpIsbn() async {
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Look up an ISBN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ISBN',
            helperText: 'The 10 or 13 digits from the back of the book',
          ),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Look up'),
          ),
        ],
      ),
    );
    final isbn =
        (typed ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (isbn.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    OpenLibraryBook? found;
    try {
      found = await widget.client.lookupIsbn(isbn);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not reach Open Library. Check your connection.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _addFromIsbn(isbn, found);
  }

  Future<void> _syncNow() async {
    if (!widget.pcSync.paired) {
      _openSettings();
      return;
    }
    await runManualSync(context, widget.pcSync);
  }

  Future<void> _addFromIsbn(String isbn, OpenLibraryBook? found) async {
    if (found == null) {
      final addManually = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Book not found'),
          content: Text(
            'Open Library has no match for ISBN $isbn. '
            'Do you want to add it yourself?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add manually'),
            ),
          ],
        ),
      );
      if (addManually != true || !mounted) return;
      await _addManually(isbn: isbn);
      return;
    }

    final shelf = await chooseShelfForNewBook(context, widget.settings);
    if (shelf == null || !mounted) return;
    await widget.repository.add(
      title: found.title,
      author: found.author,
      shelf: shelf,
      tags: widget.settings.defaultTags,
      format: widget.settings.defaultFormat,
      isbn: isbn,
      coverUrl: found.coverUrl,
      firstPublishYear: found.firstPublishYear,
      pages: found.pages,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${found.title}" to ${shelf.label}')),
    );
  }

  Widget _list(List<Book> books) {
    if (widget.settings.display == DisplayMode.table) {
      return BookTable(
        books: sortBooks(
          books,
          widget.settings.sortField,
          ascending: widget.settings.ascending,
        ),
        repository: widget.repository,
        selected: _selected,
        onSetSelected: (ids) => setState(() {
          _selected
            ..clear()
            ..addAll(ids);
        }),
        onOpen: _openBook,
        onContextMenu: _showBookMenu,
        ratingAsNumber: widget.settings.ratingAsNumber,
        emptyText: _filtering
            ? 'No books on this shelf match your search or filters.'
            : 'No books on this shelf yet.',
      );
    }
    return _shelfList(books);
  }

  Widget _shelfList(List<Book> books) => _ShelfList(
        books: sortBooks(
          books,
          widget.settings.sortField,
          ascending: widget.settings.ascending,
        ),
        display: widget.settings.display,
        filtering: _filtering,
        selected: _selected,
        onOpen: (book) =>
            _selected.isEmpty ? _openBook(book) : _toggleSelected(book),
        onSelect: _toggleSelected,
        onMove: widget.repository.moveTo,
        showFormat: widget.settings.showFormatOnCards,
        showTags: widget.settings.showTagsOnCards,
        ratingAsNumber: widget.settings.ratingAsNumber,
        current: _wide ? _currentId : null,
        onContextMenu: _showBookMenu,
        coverScale: widget.settings.coverScale,
      );

  List<String> get _collections =>
      allCollectionNames(widget.settings, widget.repository);

  String _sortLabel(SortField field) {
    if (field != widget.settings.sortField) return field.label;
    return '${field.label} ${widget.settings.ascending ? '↑' : '↓'}';
  }

  AppBar _buildAppBar(PreferredSizeWidget tabBar) {
    if (_selected.isNotEmpty) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Move to shelf',
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: _moveSelected,
          ),
          IconButton(
            tooltip: 'Add a tag',
            icon: const Icon(Icons.label_outline),
            onPressed: _tagSelected,
          ),
          IconButton(
            tooltip: 'Add to a shelf of your own',
            icon: const Icon(Icons.playlist_add),
            onPressed: _addSelectedToShelf,
          ),
          IconButton(
            tooltip: 'Move to trash',
            icon: const Icon(Icons.delete_outline),
            onPressed: _trashSelected,
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _changeFormatSelected,
                child: const Text('Change format'),
              ),
              PopupMenuItem(
                value: _changeAuthorSelected,
                child: const Text('Change author'),
              ),
              PopupMenuItem(
                value: _setPrioritySelected,
                child: const Text('Set priority'),
              ),
            ],
          ),
        ],
        bottom: tabBar,
      );
    }
    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back),
          onPressed: _stopSearching,
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Title, author, ISBN or tag',
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(_searchController.clear),
            ),
        ],
        bottom: tabBar,
      );
    }
    return AppBar(
      title: const Text('Library'),
      actions: [
        IconButton(
          tooltip: 'Search (Ctrl+F)',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
        ),
        PopupMenuButton<SortField>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort',
          onSelected: widget.settings.setSort,
          itemBuilder: (_) => [
            for (final field in SortField.values)
              CheckedPopupMenuItem<SortField>(
                value: field,
                checked: field == widget.settings.sortField,
                child: Text(_sortLabel(field)),
              ),
          ],
        ),
        PopupMenuButton<DisplayMode>(
          tooltip: 'View',
          icon: Icon(switch (widget.settings.display) {
            DisplayMode.list => Icons.view_list,
            DisplayMode.grid => Icons.grid_view,
            DisplayMode.table => Icons.table_rows_outlined,
          }),
          onSelected: widget.settings.setDisplay,
          itemBuilder: (_) => [
            for (final (mode, label) in [
              (DisplayMode.list, 'List'),
              (DisplayMode.grid, 'Grid'),
              (DisplayMode.table, 'Table'),
            ])
              CheckedPopupMenuItem(
                value: mode,
                checked: widget.settings.display == mode,
                child: Text(label),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<DisplayMode>(
              onTap: () => showCoverSizeDialog(context, widget.settings),
              child: const Text('Cover size...'),
            ),
          ],
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'More',
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _openShelves,
              child: const Text('Your shelves'),
            ),
            PopupMenuItem(
              value: _openDuplicates,
              child: const Text('Find duplicates'),
            ),
            PopupMenuItem(value: _openTrash, child: const Text('Trash')),
          ],
        ),
      ],
      bottom: tabBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.settings, widget.repository]),
      builder: (context, _) => _frame(DefaultTabController(
        key: ValueKey(_collections.length),
        length: Shelf.values.length + _collections.length,
        child: PopScope(
          canPop: _selected.isEmpty && !_searching,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_selected.isNotEmpty) {
              setState(_selected.clear);
            } else {
              _stopSearching();
            }
          },
          child: Scaffold(
            appBar: _buildAppBar(
              TabBar(
                isScrollable: true,
                tabs: [
                  for (final shelf in widget.settings.shelfOrder)
                    Tab(
                      text: '${shelf.label} '
                          '(${widget.repository.booksOn(shelf).length})',
                    ),
                  for (final name in _collections)
                    Tab(
                      text: '$name '
                          '(${widget.repository.booksInCollection(name).length})',
                    ),
                ],
              ),
            ),
            body: ListenableBuilder(
              listenable: widget.repository,
              builder: (context, _) {
                if (!widget.repository.isLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allTags = widget.repository.allTags;
                // Forget filters for tags that no longer exist on any book,
                // and selections for books that are gone.
                _selectedTags.retainAll(allTags);
                _excludedTags.retainAll(allTags);
                _selected.retainAll({
                  for (final book in widget.repository.books) book.id,
                });
                return Column(
                  children: [
                    ListenableBuilder(
                      listenable: widget.pcSync,
                      builder: (context, _) {
                        final plan = widget.pcSync.pendingReview;
                        if (plan == null) return const SizedBox.shrink();
                        final removals = plan.removals;
                        return MaterialBanner(
                          leading: const Icon(Icons.sync_problem),
                          content: Text(
                            'A sync with your phone is waiting for you: it '
                            'would remove $removals '
                            '${removals == 1 ? 'book' : 'books'}.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: widget.pcSync.dismissPending,
                              child: const Text('Not now'),
                            ),
                            TextButton(
                              onPressed: _syncNow,
                              child: const Text('Review'),
                            ),
                          ],
                        );
                      },
                    ),
                    if (widget.settings.backupDue(
                      bookCount: widget.repository.books.length,
                    ))
                      MaterialBanner(
                        content: const Text(
                          'It has been a while since your last backup.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                widget.settings.snoozeBackupReminder(),
                            child: const Text('Later'),
                          ),
                          TextButton(
                            onPressed: _openSettings,
                            child: const Text('Back up'),
                          ),
                        ],
                      ),
                    _FilterBar(
                      chips: [
                        FilterChip(
                          avatar: const Icon(Icons.favorite, size: 18),
                          label: const Text('Favorites'),
                          selected: _favoritesOnly,
                          onSelected: (value) =>
                              setState(() => _favoritesOnly = value),
                        ),
                        for (final format in BookFormat.values)
                          FilterChip(
                            label: Text(format.label),
                            selected: _formats.contains(format),
                            onSelected: (_) => _toggleFormat(format),
                          ),
                        if (widget.repository.finishedYears.isNotEmpty)
                          FilterChip(
                            label: Text(
                              _finishYear == null
                                  ? 'Year finished'
                                  : 'Finished $_finishYear',
                            ),
                            selected: _finishYear != null,
                            onSelected: (_) => _chooseFinishYear(),
                          ),
                        if (_selectedTags.length > 1)
                          ActionChip(
                            label: Text(
                              _matchAllTags
                                  ? 'Match all tags'
                                  : 'Match any tag',
                            ),
                            onPressed: () =>
                                setState(() => _matchAllTags = !_matchAllTags),
                          ),
                        for (final tag in allTags)
                          FilterChip(
                            tooltip: 'Tap to show these books, '
                                'tap again to hide them',
                            avatar: _excludedTags.contains(tag)
                                ? const Icon(Icons.block, size: 18)
                                : null,
                            label: Text(
                              tag,
                              style: _excludedTags.contains(tag)
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                            selected: _selectedTags.contains(tag) ||
                                _excludedTags.contains(tag),
                            onSelected: (_) => _cycleTag(tag),
                          ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final shelf in widget.settings.shelfOrder)
                            _list(
                              widget.repository.booksOn(
                                shelf,
                                tags: _selectedTags,
                                matchAllTags: _matchAllTags,
                                excludedTags: _excludedTags,
                                finishYear: _finishYear,
                                query: _searchController.text,
                                favoritesOnly: _favoritesOnly,
                                formats: _formats,
                              ),
                            ),
                          for (final name in _collections)
                            _list(
                              widget.repository.booksInCollection(
                                name,
                                tags: _selectedTags,
                                matchAllTags: _matchAllTags,
                                excludedTags: _excludedTags,
                                finishYear: _finishYear,
                                query: _searchController.text,
                                favoritesOnly: _favoritesOnly,
                                formats: _formats,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            floatingActionButton: _selected.isEmpty
                ? FloatingActionButton(
                    tooltip: 'Add book (Ctrl+N)',
                    onPressed: _addBook,
                    child: const Icon(Icons.add),
                  )
                : null,
          ),
        ),
      )),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => chips[index],
      ),
    );
  }
}

class _ShelfList extends StatelessWidget {
  const _ShelfList({
    required this.books,
    required this.display,
    required this.filtering,
    required this.selected,
    required this.onOpen,
    required this.onSelect,
    required this.onMove,
    required this.showFormat,
    required this.showTags,
    required this.ratingAsNumber,
    required this.current,
    required this.onContextMenu,
    required this.coverScale,
  });

  final List<Book> books;
  final DisplayMode display;
  final bool filtering;
  final Set<String> selected;
  final void Function(Book book) onOpen;
  final void Function(Book book) onSelect;
  final void Function(String id, Shelf shelf) onMove;
  final bool showFormat;
  final bool showTags;
  final bool ratingAsNumber;

  /// The book open beside the list, highlighted.
  final String? current;
  final void Function(Book book, Offset position) onContextMenu;

  /// How big the covers are in the grid; 1 is the normal size.
  final double coverScale;

  List<String> _subtitleLines(Book book) {
    final format = book.format;
    final rating = book.rating;
    final priority = book.priority;
    final first = [
      if (book.author.isNotEmpty) book.author,
      if (showFormat && format != null) format.label,
      if (rating != null) ratingText(rating, asNumber: ratingAsNumber),
      if (book.shelf == Shelf.forLater && priority != null)
        '${priority.label} priority',
      if (book.shelf == Shelf.inProgress && book.progress != null)
        '${(book.progress! * 100).round()}% read',
    ].join(' · ');
    return [
      if (first.isNotEmpty) first,
      if (showTags && book.tags.isNotEmpty) book.tags.join(' · '),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            filtering
                ? 'No books on this shelf match your search or filters.'
                : 'No books on this shelf yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selecting = selected.isNotEmpty;

    if (display == DisplayMode.grid) {
      final highlight = Theme.of(context).colorScheme.primaryContainer;
      final coverWidth = 110 * coverScale;
      final coverHeight = 160 * coverScale;
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: coverWidth + 20,
          mainAxisExtent: coverHeight + 60,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return InkWell(
            onTap: () => onOpen(book),
            onLongPress: () => onSelect(book),
            onSecondaryTapDown: (details) =>
                onContextMenu(book, details.globalPosition),
            child: Container(
              color: selected.contains(book.id) || book.id == current
                  ? highlight
                  : null,
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      BookCover(
                        coverUrl: book.coverUrl,
                        width: coverWidth,
                        height: coverHeight,
                      ),
                      if (book.favorite)
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.favorite,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final lines = _subtitleLines(book);
        return GestureDetector(
          onSecondaryTapDown: (details) =>
              onContextMenu(book, details.globalPosition),
          child: ListTile(
          selected: selected.contains(book.id) || book.id == current,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          leading: BookCover(
            coverUrl: book.coverUrl,
          ),
          title: Text(book.title),
          subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
          isThreeLine: lines.length > 1,
          onTap: () => onOpen(book),
          onLongPress: () => onSelect(book),
          trailing: selecting
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (book.favorite)
                      const Icon(
                        Icons.favorite,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                    PopupMenuButton<Shelf>(
                      tooltip: 'Move to shelf',
                      onSelected: (shelf) => onMove(book.id, shelf),
                      itemBuilder: (_) => [
                        for (final shelf in Shelf.values)
                          if (shelf != book.shelf)
                            PopupMenuItem(
                              value: shelf,
                              child: Text(shelf.label),
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
