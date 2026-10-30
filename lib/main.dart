import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/app_settings.dart';
import 'data/auto_backup.dart';
import 'data/book_repository.dart';
import 'data/file_io.dart';
import 'data/open_library_client.dart';
import 'data/pc_sync.dart';
import 'data/secure_code_store.dart';
import 'data/sqlite_book_store.dart';
import 'data/theme_options.dart';
import 'screens/library_screen.dart';
import 'screens/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // C:\Users\<you>\AppData\Roaming\...\chapterly
  final dataDir = await getApplicationSupportDirectory();
  await Directory(dataDir.path).create(recursive: true);
  final repository = BookRepository(
    await SqliteBookStore.open(p.join(dataDir.path, 'chapterly.db')),
  );
  await repository.load();
  final settings = await AppSettings.load();
  final pcSync = PcSync(
    repository: repository,
    settings: settings,
    codeStore: const SecureCodeStore(),
  );
  await pcSync.load();
  WidgetsBinding.instance.addObserver(
    AutoBackupObserver(repository: repository, settings: settings),
  );
  // Not awaited: the app opens while the backup is written.
  runAutoBackup(repository, settings);
  runApp(
    ChapterlyApp(
      repository: repository,
      client: OpenLibraryClient(),
      settings: settings,
      pcSync: pcSync,
      fileIo: const FileIo(),
    ),
  );
}

class ChapterlyApp extends StatelessWidget {
  const ChapterlyApp({
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Chapterly',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(settings, Brightness.light),
        darkTheme: buildTheme(settings, Brightness.dark),
        themeMode: settings.themeMode,
        builder: (context, child) => LockGate(
          settings: settings,
          child: child ?? const SizedBox.shrink(),
        ),
        home: LibraryScreen(
          repository: repository,
          client: client,
          settings: settings,
          pcSync: pcSync,
          fileIo: fileIo,
        ),
      ),
    );
  }
}
