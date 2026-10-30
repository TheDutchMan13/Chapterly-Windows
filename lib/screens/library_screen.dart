import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/book_sorting.dart';
import '../data/collections.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/pc_sync.dart';
import '../data/rating_text.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../models/wish_priority.dart';
import '../widgets/book_cover.dart';
import 'add_book_dialog.dart';
import 'book_detail_screen.dart';
import 'duplicates_screen.dart';
import 'manage_shelves_screen.dart';
import 'next_up_screen.dart';
import 'read_next_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shelf_picker.dart';
import 'statistics_screen.dart';
import 'trash_screen.dart';

enum _AddChoice { search, isbn, manual }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.settings,
    required this.pcSync,
    required this.fileIo,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;
  final PcSync pcSync;
  final FileIo fileIo;

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

  @override
  void dispose() {
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

  void _openReadNext() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadNextScreen(
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
        ),
      ),
    );
  }

  void _openNextUp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NextUpScreen(
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
        ),
      ),
    );
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

  void _openStatistics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsScreen(
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
        ),
      ),
    );
  }

  void _openSettings() {
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
      case _AddChoice.manual:
        await _addManually();
    }
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
    final messenger = ScaffoldMessenger.of(context);
    final problem = await widget.pcSync.syncNow();
    messenger.showSnackBar(
      SnackBar(content: Text(problem ?? 'Synced with your phone')),
    );
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

  Widget _list(List<Book> books) => _ShelfList(
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
      title: const Text('Chapterly'),
      actions: [
        ListenableBuilder(
          listenable: widget.pcSync,
          builder: (context, _) => IconButton(
            tooltip: widget.pcSync.paired
                ? 'Sync with your phone'
                : 'Set up sync with your phone',
            icon: widget.pcSync.busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: widget.pcSync.busy ? null : _syncNow,
          ),
        ),
        IconButton(
          tooltip: 'Search',
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
        IconButton(
          tooltip: widget.settings.display == DisplayMode.grid
              ? 'Show as list'
              : 'Show as grid',
          icon: Icon(
            widget.settings.display == DisplayMode.grid
                ? Icons.view_list
                : Icons.grid_view,
          ),
          onPressed: widget.settings.toggleDisplay,
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'More',
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _openStatistics,
              child: const Text('Statistics'),
            ),
            PopupMenuItem(
              value: _openNextUp,
              child: const Text('Next up (reading order)'),
            ),
            PopupMenuItem(
              value: _openReadNext,
              child: const Text('What should I read next?'),
            ),
            PopupMenuItem(
              value: _openShelves,
              child: const Text('Your shelves'),
            ),
            PopupMenuItem(
              value: _openDuplicates,
              child: const Text('Find duplicates'),
            ),
            PopupMenuItem(value: _openTrash, child: const Text('Trash')),
            PopupMenuItem(
              value: _openSettings,
              child: const Text('Settings'),
            ),
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
      builder: (context, _) => DefaultTabController(
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
                    tooltip: 'Add book',
                    onPressed: _addBook,
                    child: const Icon(Icons.add),
                  )
                : null,
          ),
        ),
      ),
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
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisExtent: 220,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return InkWell(
            onTap: () => onOpen(book),
            onLongPress: () => onSelect(book),
            child: Container(
              color: selected.contains(book.id) ? highlight : null,
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      BookCover(
                        coverUrl: book.coverUrl,
                        width: 110,
                        height: 160,
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
        return ListTile(
          selected: selected.contains(book.id),
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
        );
      },
    );
  }
}
