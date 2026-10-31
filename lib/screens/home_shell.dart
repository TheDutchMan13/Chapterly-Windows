import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/pc_sync.dart';
import '../widgets/sync_status.dart';
import 'library_screen.dart';
import 'next_up_screen.dart';
import 'read_next_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

/// The main window: a side menu with Library, Statistics, Next up, Read next
/// and Settings, and how syncing is going at the bottom. Every page stays
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

  void _go(int index) {
    if (index != _index) setState(() => _index = index);
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
                      leading: const SizedBox(height: 4),
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
