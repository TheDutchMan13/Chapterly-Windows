import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

import '../server/server_platform.dart';
import 'profiles.dart';
import 'secure_code_store.dart';

/// The open profile's folder, set at start-up.
Directory? openProfileDir;

/// Where a profile keeps everything on this PC: its database, sync state,
/// reader and audiobook lists, book server state and its copies of book
/// files. The first profile uses the app's data folder, as before
/// profiles; the others use profiles\<id> in it.
Future<Directory> profileDataDir(String id) async {
  final base = await getApplicationSupportDirectory();
  final dir = id == mainProfileId
      ? Directory(base.path)
      : Directory(p.join(base.path, 'profiles', id));
  await dir.create(recursive: true);
  return dir;
}

/// The folder in Documents\Chapterly for a profile's automatic backups,
/// named after the profile. Null for the first profile, whose backups stay
/// in Documents\Chapterly itself.
String? profileBackupFolder(Profile profile) {
  if (profile.isMain) return null;
  final safe =
      profile.name.trim().replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_').trim();
  return safe.isEmpty ? profile.id : safe;
}

/// The first profile's files in the app's data folder. The folder also
/// holds things that belong to every profile (such as the settings file
/// and the other profiles), so only these are removed.
const _mainProfileFiles = [
  'chapterly.db',
  'chapterly.db-journal',
  'chapterly.db-wal',
  'chapterly.db-shm',
  'sync_base.json',
  'audio_library.json',
  'audio_bookmarks.json',
  'audio_bookmarks.moved.json',
  'ebook_library.json',
  'scan_state.json',
  'cover_prints.json',
  'book_server.json',
  'book_server_library.json',
  'books',
  'server_audio',
];

/// Removes a profile's books, files, pairing code and book server token
/// from this PC. Its automatic backups in Documents\Chapterly are kept.
Future<void> removeProfileFiles(String id) async {
  try {
    await SecureCodeStore(storageKey: SecureCodeStore.keyFor(id)).delete();
  } catch (_) {
    // No code saved.
  }
  try {
    await SecureTokenStore(storageKey: SecureTokenStore.keyFor(id)).delete();
  } catch (_) {
    // No token saved.
  }
  final base = await getApplicationSupportDirectory();
  final paths = id == mainProfileId
      ? [for (final name in _mainProfileFiles) p.join(base.path, name)]
      : [p.join(base.path, 'profiles', id)];
  for (final path in paths) {
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(path).delete();
      }
    } on FileSystemException {
      // Left behind; it does no harm.
    }
  }
}

/// Opens Chapterly again, so it starts with the profile that was just
/// chosen, and closes this copy.
Future<void> restartChapterly() async {
  try {
    await tray.trayManager.destroy();
  } catch (_) {
    // No tray icon.
  }
  await Process.start(
    Platform.resolvedExecutable,
    const [],
    mode: ProcessStartMode.detached,
  );
  exit(0);
}
