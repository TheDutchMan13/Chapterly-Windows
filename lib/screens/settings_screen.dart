import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_info.dart';
import '../data/app_settings.dart';
import '../data/auto_backup.dart';
import '../data/backup.dart';
import '../data/book_repository.dart';
import '../data/csv.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/kindle_clippings.dart';
import '../data/library_scan.dart';
import '../data/pc_sync.dart';
import '../data/theme_options.dart';
import '../data/update_check.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'pin_dialogs.dart';
import 'scan_settings.dart';
import 'shelf_order_screen.dart';
import 'sync_preview.dart';
import 'whats_new_screen.dart';

/// Accent colour and font, backup and restore, and CSV import and export.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.pcSync,
    required this.fileIo,
  });

  final BookRepository repository;
  final AppSettings settings;
  final PcSync pcSync;
  final FileIo fileIo;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _editDefaultTags() async {
    final controller = TextEditingController(
      text: widget.settings.defaultTags.join(', '),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tags for new books'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tags',
            helperText: 'Separate with commas. Leave empty for none.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (saved != true) return;
    widget.settings.setDefaultTags(parseTags(text));
  }

  void _openShelfOrder() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShelfOrderScreen(settings: widget.settings),
      ),
    );
  }

  void _openChangelog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WhatsNewScreen()),
    );
  }

  Future<void> _openSource() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(sourceCodeUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  void _openLicence() {
    showLicensePage(
      context: context,
      applicationName: appName,
      applicationVersion: appVersion,
      applicationLegalese: '$licenceName. Full text: $licenceUrl',
    );
  }

  Future<void> _setPin() async {
    final pin = await askNewPin(context);
    if (pin == null) return;
    widget.settings.setPin(pin);
  }

  Future<void> _changePin() async {
    if (!await confirmCurrentPin(context, widget.settings)) return;
    if (!mounted) return;
    await _setPin();
  }

  Future<void> _removePin() async {
    if (!await confirmCurrentPin(context, widget.settings)) return;
    widget.settings.clearPin();
  }

  Widget _lockSettings() {
    final settings = widget.settings;
    if (!settings.pinEnabled) {
      return ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('App lock'),
        subtitle: const Text('Ask for a PIN when Chapterly opens.'),
        onTap: _setPin,
      );
    }
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.lock),
          title: const Text('Change PIN'),
          onTap: _changePin,
        ),
        ListTile(
          leading: const Icon(Icons.lock_open),
          title: const Text('Turn off app lock'),
          onTap: _removePin,
        ),
        ListTile(
          title: const Text('Lock after'),
          trailing: DropdownButton<int>(
            value: settings.lockAfterSeconds,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Immediately')),
              DropdownMenuItem(value: 30, child: Text('30 seconds')),
              DropdownMenuItem(value: 60, child: Text('1 minute')),
              DropdownMenuItem(value: 300, child: Text('5 minutes')),
            ],
            onChanged: (seconds) {
              if (seconds != null) settings.setLockAfterSeconds(seconds);
            },
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('If you forget the PIN'),
          subtitle: Text(
            'The only way back in is clearing the app data, which erases '
            'your library. Keep a backup. PC sync still answers while the '
            'app is locked.',
          ),
        ),
      ],
    );
  }

  bool _busy = false;

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Runs [action], shows a message if it fails, and blocks double taps.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) _say(error.message);
    } catch (_) {
      if (mounted) _say('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showShortcuts() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: const Text(
          'Ctrl+F              Search\n'
          'Ctrl+N              Add a book\n'
          'Ctrl+Shift+N    Add several books from a list\n'
          'Ctrl+O              Add a book file or audiobook\n'
          'Ctrl+S              Sync with your phone\n'
          'Ctrl+V              Paste a picture as the open book\'s cover\n'
          'Ctrl+,               Settings\n'
          'Ctrl+1 to Ctrl+5  Library, Statistics, Next up, Read next, '
          'Settings\n'
          'Ctrl+= / Ctrl+-   Bigger or smaller covers in the grid\n'
          'Esc                   Close the selection, the search or the '
          'open book\n'
          '\n'
          'In the reader: Page Down, Space or the right arrow for the next '
          'screen; Page Up or the left arrow to go back; Ctrl+F search; '
          'Ctrl+B bookmark; Ctrl+R read aloud; Ctrl+= and Ctrl+- text '
          'size; Esc to close.\n'
          '\n'
          'Right-click a book for more actions. Drop a backup, a CSV file '
          'or My Clippings.txt on the window to import it, or a picture to '
          'make it the open book\'s cover.\n'
          '\n'
          'In the table view: double-click a title, author or page count to '
          'change it, click a shelf, rating or format to pick one, and '
          'Ctrl+click or Shift+click to select several books.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      widget.settings.setLastUpdateCheck(DateTime.now());
      final update = await checkForUpdate();
      if (update == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You have the newest version.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
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
    } on UpdateCheckFailure {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't reach GitHub. Check your connection."),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportBackup() => _run(() async {
        await widget.fileIo.shareText(
          fileName: 'chapterly-backup-${formatDate(DateTime.now())}.json',
          content: encodeBackup(widget.repository.allBooks),
          mimeType: 'application/json',
          subject: 'Chapterly backup',
        );
        widget.settings.markBackedUp();
      });

  Future<void> _backUpNow() => _run(() async {
        await runAutoBackup(widget.repository, widget.settings, force: true);
        if (!mounted) return;
        final error = widget.settings.lastAutoBackupError;
        _say(error == null ? 'Backup saved.' : 'Backup failed: $error');
      });

  String _autoBackupText() {
    final settings = widget.settings;
    final error = settings.lastAutoBackupError;
    if (error != null) return 'Last try failed: $error';
    final at = settings.lastAutoBackupAt;
    if (at == null) return 'None yet';
    final path = settings.lastAutoBackupPath;
    return path == null
        ? formatDateTime(at)
        : '${formatDateTime(at)}\n$path';
  }

  Future<void> _restoreBackup() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final books = decodeBackup(text);
        if (!mounted) return;
        final confirmed = await _confirm(
          title: 'Restore backup?',
          message: 'This replaces your ${widget.repository.books.length} '
              'current books with the ${books.length} books in the backup.',
          action: 'Restore',
        );
        if (!confirmed || !mounted) return;
        await widget.repository.replaceAll(books);
        if (mounted) _say('Restored ${books.length} books.');
      });

  Future<void> _exportCsv() => _run(() async {
        await widget.fileIo.shareText(
          fileName: 'chapterly-books-${formatDate(DateTime.now())}.csv',
          content: encodeBooksCsv(widget.repository.books),
          mimeType: 'text/csv',
          subject: 'Chapterly books',
        );
      });

  Future<void> _importCsv() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final result = importBooksFromCsv(text);
        final added = await widget.repository.importBooks(result.books);
        final duplicates = result.books.length - added;
        if (!mounted) return;
        final parts = ['Imported $added book${added == 1 ? '' : 's'}'];
        if (duplicates > 0) parts.add('$duplicates already in your library');
        if (result.skipped > 0) parts.add('${result.skipped} skipped');
        _say('${parts.join(', ')}.');
      });

  Future<void> _importKindle() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final clippings = parseKindleClippings(text);
        if (clippings.isEmpty) {
          throw const FormatException(
            'No highlights found. Pick the My Clippings.txt file from your '
            'Kindle.',
          );
        }
        final match = matchClippings(widget.repository.books, clippings);
        await widget.repository.addQuotesToBooks(match.quotesByBook);
        if (!mounted) return;
        final added = match.added;
        final lines = <String>[
          'Added $added ${added == 1 ? 'quote' : 'quotes'} to '
              '${match.quotesByBook.length} '
              '${match.quotesByBook.length == 1 ? 'book' : 'books'}.',
          if (match.alreadySaved > 0)
            '${match.alreadySaved} ${match.alreadySaved == 1 ? 'was' : 'were'}'
                ' already saved.',
        ];
        final missing = match.unmatchedTitles;
        if (missing.isNotEmpty) {
          lines.add('');
          lines.add('No book in your library matches:');
          for (final title in missing.take(15)) {
            lines.add('• $title');
          }
          if (missing.length > 15) lines.add('and ${missing.length - 15} more');
          lines.add('');
          lines.add('Add those books, then import again. Highlights you '
              'already have are not added twice.');
        }
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Kindle highlights'),
            content: SingleChildScrollView(child: Text(lines.join('\n'))),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(),
          const _SectionHeader('Appearance'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {widget.settings.themeMode},
                    onSelectionChanged: (choice) =>
                        widget.settings.setThemeMode(choice.first),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Pure black in dark mode'),
                  subtitle: const Text(
                    'True black instead of dark grey. Can save battery on '
                    'OLED screens.',
                  ),
                  value: widget.settings.pureBlack,
                  onChanged: widget.settings.setPureBlack,
                ),
                SwitchListTile(
                  title: const Text('Paper look in light mode'),
                  subtitle: const Text(
                    'A warm, cream page colour instead of white.',
                  ),
                  value: widget.settings.paperLight,
                  onChanged: widget.settings.setPaperLight,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final choice in accentChoices)
                        _AccentDot(
                          choice: choice,
                          selected:
                              choice.color.toARGB32() == widget.settings.accent,
                          onTap: () => widget.settings
                              .setAccent(choice.color.toARGB32()),
                        ),
                      _CustomAccentDot(
                        current: Color(widget.settings.accent),
                        selected: !accentChoices.any(
                          (choice) =>
                              choice.color.toARGB32() ==
                              widget.settings.accent,
                        ),
                        onPick: (colour) =>
                            widget.settings.setAccent(colour.toARGB32()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: widget.settings.fontFamily ?? '',
                  onChanged: (value) => widget.settings.setFontFamily(
                    value == null || value.isEmpty ? null : value,
                  ),
                  child: Column(
                    children: [
                      for (final font in fontChoices)
                        RadioListTile<String>(
                          value: font.family ?? '',
                          title: Text(
                            font.label,
                            style: TextStyle(fontFamily: font.family),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _SectionHeader('Adding books'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              children: [
                ListTile(
                  title: const Text('Put new books on'),
                  trailing: DropdownButton<Shelf?>(
                    value: widget.settings.defaultShelf,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Ask every time'),
                      ),
                      for (final shelf in Shelf.values)
                        DropdownMenuItem(
                          value: shelf,
                          child: Text(shelf.label),
                        ),
                    ],
                    onChanged: widget.settings.setDefaultShelf,
                  ),
                ),
                ListTile(
                  title: const Text('Format of new books'),
                  trailing: DropdownButton<BookFormat?>(
                    value: widget.settings.defaultFormat,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Not set'),
                      ),
                      for (final format in BookFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(format.label),
                        ),
                    ],
                    onChanged: widget.settings.setDefaultFormat,
                  ),
                ),
                ListTile(
                  title: const Text('Tags for new books'),
                  subtitle: Text(
                    widget.settings.defaultTags.isEmpty
                        ? 'None'
                        : widget.settings.defaultTags.join(', '),
                  ),
                  onTap: _editDefaultTags,
                ),
              ],
            ),
          ),
          const _SectionHeader('Library'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              children: [
                SwitchListTile(
                  title: const Text('Show ratings as numbers'),
                  subtitle: const Text('4/5 instead of stars'),
                  value: widget.settings.ratingAsNumber,
                  onChanged: widget.settings.setRatingAsNumber,
                ),
                SwitchListTile(
                  title: const Text('Show format on book cards'),
                  value: widget.settings.showFormatOnCards,
                  onChanged: widget.settings.setShowFormatOnCards,
                ),
                SwitchListTile(
                  title: const Text('Show tags on book cards'),
                  value: widget.settings.showTagsOnCards,
                  onChanged: widget.settings.setShowTagsOnCards,
                ),
                ListTile(
                  title: const Text('Order of shelf tabs'),
                  subtitle: Text(
                    [for (final s in widget.settings.shelfOrder) s.label]
                        .join(' · '),
                  ),
                  onTap: _openShelfOrder,
                ),
              ],
            ),
          ),
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export backup'),
            subtitle: const Text(
              'Save your whole library as a file. Send it to Drive, email '
              'or Files to keep it safe.',
            ),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore backup'),
            subtitle: const Text(
              'Replace your library with a backup file made by Chapterly.',
            ),
            onTap: _restoreBackup,
          ),
          const _SectionHeader('Automatic backups'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              children: [
                SwitchListTile(
                  title: const Text('Back up by itself'),
                  subtitle: const Text(
                    'Saves a backup file in Documents\\Chapterly when you open '
                    'the app, and keeps the last $autoBackupKeep. That folder '
                    'stays when the app is uninstalled.',
                  ),
                  value: widget.settings.autoBackup,
                  onChanged: widget.settings.setAutoBackup,
                ),
                if (widget.settings.autoBackup) ...[
                  ListTile(
                    title: const Text('How often'),
                    trailing: DropdownButton<int>(
                      value: widget.settings.autoBackupDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Every day')),
                        DropdownMenuItem(value: 7, child: Text('Every week')),
                        DropdownMenuItem(value: 30, child: Text('Every month')),
                      ],
                      onChanged: (days) {
                        if (days != null) widget.settings.setAutoBackupDays(days);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Last automatic backup'),
                    subtitle: Text(_autoBackupText()),
                    trailing: TextButton(
                      onPressed: _backUpNow,
                      child: const Text('Back up now'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const _SectionHeader('Backup reminder'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) {
              final last = widget.settings.lastBackup;
              return Column(
                children: [
                  SwitchListTile(
                    title: const Text('Remind me to back up'),
                    subtitle: Text(
                      last == null
                          ? 'No backup made yet'
                          : 'Last backup: ${formatDate(last)}',
                    ),
                    value: widget.settings.backupReminder,
                    onChanged: widget.settings.setBackupReminder,
                  ),
                  if (widget.settings.backupReminder)
                    ListTile(
                      title: const Text('Remind me after'),
                      trailing: DropdownButton<int>(
                        value: widget.settings.backupDays,
                        items: const [
                          DropdownMenuItem(value: 14, child: Text('2 weeks')),
                          DropdownMenuItem(value: 30, child: Text('1 month')),
                          DropdownMenuItem(value: 60, child: Text('2 months')),
                          DropdownMenuItem(value: 90, child: Text('3 months')),
                        ],
                        onChanged: (days) {
                          if (days != null) widget.settings.setBackupDays(days);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const _SectionHeader('Privacy'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => _lockSettings(),
          ),
          const _SectionHeader('Sync with your phone'),
          ListenableBuilder(
            listenable: Listenable.merge([widget.settings, widget.pcSync]),
            builder: (context, _) => _SyncSettings(
              settings: widget.settings,
              pcSync: widget.pcSync,
            ),
          ),
          if (LibraryScanning.scanner case final scanner?) ...[
            const _SectionHeader('Book and audiobook folders'),
            ScanSettings(
              settings: widget.settings,
              repository: widget.repository,
              scanner: scanner,
            ),
          ],
          const _SectionHeader('Spreadsheet (CSV)'),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export as CSV'),
            subtitle: const Text('Open your books in a spreadsheet app.'),
            onTap: _exportCsv,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import from CSV'),
            subtitle: const Text(
              'Add books from a Goodreads, StoryGraph or Libib export, or a '
              'Chapterly CSV. Books you already have are skipped.',
            ),
            onTap: _importCsv,
          ),
          const _SectionHeader('Kindle'),
          ListTile(
            leading: const Icon(Icons.format_quote_outlined),
            title: const Text('Import Kindle highlights'),
            subtitle: const Text(
              'Plug in your Kindle and pick its documents\\My Clippings.txt '
              'file. Highlights become quotes on books you already have.',
            ),
            onTap: _importKindle,
          ),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your library stays on this PC'),
            subtitle: Text(
              'Chapterly has no account, ads or tracking. The only internet '
              'use is searching Open Library, loading cover images and, if '
              'switched on, checking GitHub for updates. Sync talks only to '
              'your own phone on your home network.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: Text('Version'),
            subtitle: Text(appVersion),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_outlined),
            title: const Text('Keyboard shortcuts'),
            subtitle: const Text(
              'Ctrl+F search, Ctrl+N add, Ctrl+S sync, Ctrl+V paste a cover',
            ),
            onTap: _showShortcuts,
          ),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => SwitchListTile(
              secondary: const Icon(Icons.system_update_outlined),
              title: const Text('Check for updates'),
              subtitle: const Text(
                'Once a day, asks GitHub whether a newer Chapterly for '
                'Windows is out. Nothing about you or your books is sent.',
              ),
              value: widget.settings.checkUpdates,
              onChanged: widget.settings.setCheckUpdates,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Check for updates now'),
            onTap: _checkNow,
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Changelog'),
            subtitle: const Text("See what's new in Chapterly"),
            onTap: _openChangelog,
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('See on GitHub'),
            onTap: _openSource,
          ),
          ListTile(
            leading: const Icon(Icons.copyright_outlined),
            title: const Text('Licence'),
            subtitle: const Text(licenceName),
            onTap: _openLicence,
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AccentChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: choice.name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: CircleAvatar(
          backgroundColor: choice.color,
          radius: 20,
          child: selected
              ? const Icon(Icons.check, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _CustomAccentDot extends StatelessWidget {
  const _CustomAccentDot({
    required this.current,
    required this.selected,
    required this.onPick,
  });

  final Color current;
  final bool selected;
  final ValueChanged<Color> onPick;

  Future<void> _open(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColourDialog(initial: current),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Custom colour',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _open(context),
        child: CircleAvatar(
          radius: 20,
          backgroundColor: selected ? current : scheme.surfaceContainerHighest,
          child: Icon(
            selected ? Icons.check : Icons.palette_outlined,
            color: selected ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ColourDialog extends StatefulWidget {
  const _ColourDialog({required this.initial});

  final Color initial;

  @override
  State<_ColourDialog> createState() => _ColourDialogState();
}

class _ColourDialogState extends State<_ColourDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required HSVColor Function(double) change,
  }) {
    final shown = value < min ? min : (value > max ? max : value);
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Slider(
            value: shown,
            min: min,
            max: max,
            onChanged: (next) => setState(() => _hsv = change(next)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colour = _hsv.toColor();
    return AlertDialog(
      title: const Text('Custom colour'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 12),
            _slider(
              label: 'Colour',
              value: _hsv.hue,
              min: 0,
              max: 360,
              change: (v) => _hsv.withHue(v),
            ),
            _slider(
              label: 'Strength',
              value: _hsv.saturation,
              min: 0,
              max: 1,
              change: (v) => _hsv.withSaturation(v),
            ),
            _slider(
              label: 'Brightness',
              value: _hsv.value,
              min: 0.25,
              max: 1,
              change: (v) => _hsv.withValue(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(colour),
          child: const Text('Use this colour'),
        ),
      ],
    );
  }
}

class _SyncSettings extends StatefulWidget {
  const _SyncSettings({required this.settings, required this.pcSync});

  final AppSettings settings;
  final PcSync pcSync;

  @override
  State<_SyncSettings> createState() => _SyncSettingsState();
}

/// The choices for "Sync while Chapterly is open", in minutes. 0 is never.
const _syncChoices = [0, 5, 15, 30, 60];

class _SyncSettingsState extends State<_SyncSettings> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  String? _problem;
  bool _finding = false;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  String _lastSyncText() {
    final error = widget.settings.lastSyncError;
    if (error != null) return 'Failed: $error';
    final at = widget.settings.lastSyncAt;
    if (at == null) return 'Never';
    final changed = widget.settings.lastSyncChanged;
    final what = changed == 0
        ? 'nothing changed'
        : '$changed ${changed == 1 ? 'book' : 'books'} changed';
    return '${formatDateTime(at)} · $what';
  }

  /// Looks for the phone on the network. Returns its address, or null.
  Future<String?> _find() async {
    setState(() {
      _finding = true;
      _problem = null;
    });
    final found = await widget.pcSync.findPhones();
    if (!mounted) return null;
    setState(() => _finding = false);
    if (found.isEmpty) {
      setState(() {
        _problem = 'No phone found. Check that Chapterly is open on the phone '
            'with "Allow sync from my PC" on, and that both are on the same '
            'Wi-Fi. You can also type the address.';
      });
      return null;
    }
    if (found.length == 1) return found.first;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Which phone?'),
        children: [
          for (final address in found)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(address),
              child: Text(address),
            ),
        ],
      ),
    );
  }

  Future<void> _findForPairing() async {
    final address = await _find();
    if (address == null || !mounted) return;
    setState(() => _address.text = address);
  }

  Future<void> _findAgain() async {
    final messenger = ScaffoldMessenger.of(context);
    final address = await _find();
    if (address == null || !mounted) return;
    final problem = await widget.pcSync.changeAddress(address);
    if (!mounted) return;
    setState(() => _problem = problem);
    if (problem == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Found your phone at $address')),
      );
    }
  }

  Widget _findLabel(String idle) => _finding
      ? const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Looking for your phone...'),
          ],
        )
      : Text(idle);

  Future<void> _connect() async {
    setState(() => _problem = null);
    final messenger = ScaffoldMessenger.of(context);
    final problem = await widget.pcSync.pair(
      address: _address.text,
      code: _code.text,
    );
    if (!mounted) return;
    setState(() => _problem = problem);
    if (problem == null) {
      _code.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Connected and synced with your phone')),
      );
    }
  }

  Future<void> _syncNow() => runManualSync(context, widget.pcSync);

  Future<void> _forget() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget this phone?'),
        content: const Text(
          'Your books stay on this PC. To sync again, enter the address and '
          'pairing code from your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (sure == true) await widget.pcSync.forget();
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.pcSync;
    if (sync.paired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Your phone'),
            subtitle: Text(widget.settings.syncAddress ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Last sync'),
            subtitle: Text(_lastSyncText()),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('Sync when Chapterly opens'),
            subtitle: const Text(
              'Only if your phone is there. Says nothing when it is not.',
            ),
            value: widget.settings.syncOnOpen,
            onChanged: widget.settings.setSyncOnOpen,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Sync while Chapterly is open'),
            subtitle: const Text(
              'Quietly, whenever your phone is there.',
            ),
            trailing: DropdownButton<int>(
              value: _syncChoices.contains(widget.settings.syncEveryMinutes)
                  ? widget.settings.syncEveryMinutes
                  : 15,
              onChanged: (minutes) {
                if (minutes != null) {
                  widget.settings.setSyncEveryMinutes(minutes);
                }
              },
              items: [
                for (final minutes in _syncChoices)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(
                      minutes == 0
                          ? 'Never'
                          : minutes == 60
                              ? 'Every hour'
                              : 'Every $minutes minutes',
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fact_check_outlined),
            title: const Text('Show changes before syncing'),
            subtitle: const Text(
              'Sync now shows what will change first. Automatic syncs wait '
              'for you when they would remove books.',
            ),
            value: widget.settings.reviewSync,
            onChanged: widget.settings.setReviewSync,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: sync.busy ? null : _syncNow,
                  icon: const Icon(Icons.sync),
                  label: Text(sync.busy ? 'Syncing...' : 'Sync now'),
                ),
                OutlinedButton(
                  onPressed: sync.busy ? null : _findAgain,
                  child: _findLabel('Find my phone again'),
                ),
                TextButton(
                  onPressed: sync.busy ? null : _forget,
                  child: const Text('Forget this phone'),
                ),
              ],
            ),
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                problem,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Chapterly must be open on your phone, with "Allow sync from my '
              'PC" on and both on the same Wi-Fi. The newest change to each '
              'book wins.',
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'On your phone, open Chapterly and go to Settings > Sync with a '
            'PC. Switch on "Allow sync from my PC", then type the address '
            'and pairing code it shows.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: '192.168.1.20:8765',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: sync.busy ? null : _findForPairing,
              icon: const Icon(Icons.wifi_find),
              label: _findLabel('Find my phone'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              hintText: 'ABCD-EFGH-JKLM-NPQR',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => sync.busy ? null : _connect(),
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                problem,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: sync.busy ? null : _connect,
            icon: sync.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: const Text('Connect and sync'),
          ),
          const SizedBox(height: 8),
          const Text(
            'The pairing code is kept in Windows Credential Manager. The '
            'first sync merges both libraries; nothing is deleted.',
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
