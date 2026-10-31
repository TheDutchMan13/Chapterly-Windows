import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/listening.dart';
import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/pc_sync.dart';
import '../ebook/ebook_reading.dart';
import '../widgets/sync_status.dart';
import 'add_file_flow.dart';
import 'library_screen.dart';
import 'next_up_screen.dart';
import 'read_next_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

/// The main window: a side menu with Add file, Library, Statistics, Next
/// up, Read next and Settings, and how syncing is going at the bottom. Every page stays
/// alive, so the library keeps its search, filters and open book while you
/// look at another page.
class HomeShell extends StatefulWidget {
  const HomeShell({
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
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _settingsPage = 4;

  static const _pages = [
    (Icons.menu_book_outlined, Icons.menu_book, 'Library'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Statistics'),
    (Icons.format_list_numbered, Icons.format_list_numbered, 'Next up'),
    (Icons.lightbulb_outline, Icons.lightbulb, 'Read next'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];

  int _index = 0;

  final _addMenu = MenuController();

  /// Tells the library which book to open after Add file.
  final _openBook = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _openBook.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index != _index) setState(() => _index = index);
  }

  /// Whether this build can read books or play audiobooks (not in tests).
  bool get _canAddFiles =>
      EbookReading.library != null || Listening.controller != null;

  Future<void> _addFile(AddFileKind kind) => addFileToLibrary(
        context,
        repository: widget.repository,
        kind: kind,
        onLinked: (bookId) {
          _go(0);
          // Set twice so the same book opens again if asked again.
          _openBook.value = null;
          _openBook.value = bookId;
        },
      );

  /// The button at the top of the side menu: pick an EPUB, PDF or
  /// audiobook and it is linked to its book in the library.
  Widget _addButton(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MenuAnchor(
      controller: _addMenu,
      menuChildren: [
        if (EbookReading.library != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.chrome_reader_mode_outlined),
            onPressed: () => _addFile(AddFileKind.book),
            child: const Text('Book to read (EPUB or PDF)...'),
          ),
        if (Listening.controller != null) ...[
          MenuItemButton(
            leadingIcon: const Icon(Icons.headphones_outlined),
            onPressed: () => _addFile(AddFileKind.audioFile),
            child: const Text('Audiobook file...'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.folder_outlined),
            onPressed: () => _addFile(AddFileKind.audioFolder),
            child: const Text('Audiobook folder...'),
          ),
        ],
      ],
      builder: (context, controller, _) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Column(
          children: [
            Tooltip(
              message: 'Add a book file or audiobook (Ctrl+O)',
              waitDuration: const Duration(milliseconds: 600),
              child: IconButton.filledTonal(
                icon: const Icon(Icons.add),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
            const SizedBox(height: 4),
            Text('Add file', style: textTheme.labelMedium),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        for (var i = 0; i < _pages.length; i++)
          SingleActivator(_digits[i], control: true): () => _go(i),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            _go(_settingsPage),
        if (_canAddFiles)
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              _addMenu.open(),
      },
      child: Scaffold(
        body: Row(
          children: [
            ColoredBox(
              color: scheme.surfaceContainerLow,
              child: Column(
                children: [
                  Expanded(
                    child: NavigationRail(
                      backgroundColor: Colors.transparent,
                      selectedIndex: _index,
                      onDestinationSelected: _go,
                      labelType: NavigationRailLabelType.all,
                      groupAlignment: -1,
                      leading: _canAddFiles
                          ? _addButton(context)
                          : const SizedBox(height: 4),
                      destinations: [
                        for (var i = 0; i < _pages.length; i++)
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: '${_pages[i].$3} (Ctrl+${i + 1})',
                              waitDuration: const Duration(milliseconds: 600),
                              child: Icon(_pages[i].$1),
                            ),
                            selectedIcon: Icon(_pages[i].$2),
                            label: Text(_pages[i].$3),
                          ),
                      ],
                    ),
                  ),
                  SyncStatusButton(
                    pcSync: widget.pcSync,
                    onSetUp: () => _go(_settingsPage),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  LibraryScreen(
                    repository: widget.repository,
                    client: widget.client,
                    settings: widget.settings,
                    pcSync: widget.pcSync,
                    fileIo: widget.fileIo,
                    onOpenSettings: () => _go(_settingsPage),
                    openBookRequests: _openBook,
                  ),
                  StatisticsScreen(
                    repository: widget.repository,
                    settings: widget.settings,
                    fileIo: widget.fileIo,
                  ),
                  NextUpScreen(
                    repository: widget.repository,
                    settings: widget.settings,
                    fileIo: widget.fileIo,
                  ),
                  ReadNextScreen(
                    repository: widget.repository,
                    settings: widget.settings,
                    fileIo: widget.fileIo,
                  ),
                  SettingsScreen(
                    repository: widget.repository,
                    settings: widget.settings,
                    pcSync: widget.pcSync,
                    fileIo: widget.fileIo,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
