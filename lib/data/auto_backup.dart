import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import 'backup.dart';
import 'book_repository.dart';

/// How many automatic backups are kept in a folder. Older ones are removed.
const autoBackupKeep = 5;

const _prefix = 'chapterly-auto-';

String _two(int n) => n.toString().padLeft(2, '0');

/// chapterly-auto-2026-10-29-2141.json, so the names sort by date.
String autoBackupFileName(DateTime time) =>
    '$_prefix${time.year}-${_two(time.month)}-${_two(time.day)}-'
    '${_two(time.hour)}${_two(time.minute)}.json';

/// Documents\Chapterly first, where you can see the files. The app's own
/// data folder is the fallback.
Future<List<Directory>> autoBackupFolders() async {
  final folders = <Directory>[];
  final separator = Platform.pathSeparator;
  try {
    final documents = await getApplicationDocumentsDirectory();
    folders.add(Directory('${documents.path}${separator}Chapterly'));
  } catch (_) {
    // No Documents folder (for example in tests).
  }
  try {
    final own = await getApplicationSupportDirectory();
    folders.add(Directory('${own.path}${separator}backups'));
  } catch (_) {
    // Not available (for example in tests).
  }
  return folders;
}

/// Removes the oldest automatic backups in [folder], keeping [keep].
/// Files that cannot be removed are left alone. Returns how many went.
Future<int> pruneAutoBackups(Directory folder, {int keep = autoBackupKeep}) async {
  final files = <File>[];
  await for (final entity in folder.list()) {
    final name = entity.uri.pathSegments.last;
    if (entity is File && name.startsWith(_prefix) && name.endsWith('.json')) {
      files.add(entity);
    }
  }
  files.sort((a, b) => b.path.compareTo(a.path));
  var removed = 0;
  for (final file in files.skip(keep)) {
    try {
      await file.delete();
      removed++;
    } on FileSystemException {
      // Made by an earlier install of the app, or locked: leave it.
    }
  }
  return removed;
}

/// Writes [content] to the first of [folders] that works and tidies that
/// folder. Returns the path of the new file. Throws if no folder works.
Future<String> writeAutoBackup({
  required String content,
  required List<Directory> folders,
  required DateTime now,
}) async {
  Object? lastError;
  for (final folder in folders) {
    try {
      await folder.create(recursive: true);
      final file = File('${folder.path}/${autoBackupFileName(now)}');
      await file.writeAsString(content, flush: true);
      await pruneAutoBackups(folder);
      return file.path;
    } on FileSystemException catch (error) {
      lastError = error;
    }
  }
  throw FileSystemException(
    'No folder could be written',
    lastError is FileSystemException ? lastError.path : null,
  );
}

bool _running = false;

/// Makes an automatic backup when it is switched on and due (or always,
/// with [force]) and records the result in [settings].
Future<void> runAutoBackup(
  BookRepository repository,
  AppSettings settings, {
  bool force = false,
  DateTime? now,
}) async {
  final time = now ?? DateTime.now();
  if (_running) return;
  if (!force && !settings.autoBackupDue(time)) return;
  if (!repository.isLoaded || repository.allBooks.isEmpty) return;
  _running = true;
  try {
    final path = await writeAutoBackup(
      content: encodeBackup(repository.allBooks, now: time),
      folders: await autoBackupFolders(),
      now: time,
    );
    settings.recordAutoBackup(at: time, path: path);
  } on FileSystemException catch (error) {
    settings.recordAutoBackupError(error.message);
  } finally {
    _running = false;
  }
}

/// Runs [runAutoBackup] whenever the app comes back to the screen.
class AutoBackupObserver with WidgetsBindingObserver {
  AutoBackupObserver({required this.repository, required this.settings});

  final BookRepository repository;
  final AppSettings settings;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      runAutoBackup(repository, settings);
    }
  }
}
