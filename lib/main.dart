import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path/path.dart' as p;

import 'audio/audio_bookmarks.dart';
import 'audio/audio_library.dart';
import 'audio/listen_controller.dart';
import 'audio/listening.dart';
import 'audio/media_controls.dart';
import 'audio/windows_audio_files.dart';
import 'data/sync_three_way.dart';
import 'data/app_settings.dart';
import 'data/auto_backup.dart';
import 'data/book_repository.dart';
import 'data/file_io.dart';
import 'data/library_scan.dart';
import 'data/open_library_client.dart';
import 'data/pc_sync.dart';
import 'data/profile_files.dart';
import 'data/profiles.dart';
import 'data/reading_nudge.dart';
import 'data/secure_code_store.dart';
import 'data/sqlite_book_store.dart';
import 'data/theme_options.dart';
import 'data/tray_control.dart';
import 'data/window_control.dart';
import 'ebook/ebook_library.dart';
import 'ebook/ebook_reading.dart';
import 'ebook/windows_ebook_files.dart';
import 'models/shelf.dart';
import 'screens/book_insights.dart' show forecastFor;
import 'screens/cover_actions.dart';
import 'screens/home_shell.dart';
import 'screens/lock_gate.dart';
import 'screens/mini_player.dart';
import 'screens/mini_timer.dart';
import 'screens/now_playing.dart';
import 'server/book_server.dart';
import 'server/library_sync.dart';
import 'server/server_downloads.dart';
import 'server/server_platform.dart';
import 'server/server_state.dart';
import 'server/server_sync.dart';

/// Lets code outside the screens (such as Ctrl+V for a cover) show messages.
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

/// The profile Chapterly opened with.
String _profileId = mainProfileId;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginWindowControl.initialize();
  MiniTimer.instance.window = const PluginWindowControl();
  MiniPlayer.instance.window = const PluginWindowControl();
  // The open profile. Choosing another one restarts Chapterly with it.
  final profiles = await ProfileStore.load();
  final profile = profiles.active;
  _profileId = profile.id;
  ProfileSwitching.store = profiles;
  ProfileSwitching.switchRestarts = true;
  ProfileSwitching.removeFiles = removeProfileFiles;
  ProfileSwitching.switchTo = (id) async {
    await profiles.setActive(id);
    await _beforeRestart();
    await restartChapterly();
  };
  autoBackupSubfolder = profileBackupFolder(profile);
  // C:\Users\<you>\AppData\Roaming\...\chapterly, or profiles\<id> in it
  final dataDir = await profileDataDir(profile.id);
  openProfileDir = dataDir;
  final repository = BookRepository(
    await SqliteBookStore.open(p.join(dataDir.path, 'chapterly.db')),
  );
  await repository.load();
  final settings = await AppSettings.load(profiles.scope(profile.id));
  final pcSync = PcSync(
    repository: repository,
    settings: settings,
    codeStore: SecureCodeStore(storageKey: SecureCodeStore.keyFor(profile.id)),
    base: await SyncBase.load(File(p.join(dataDir.path, 'sync_base.json'))),
  );
  await pcSync.load();
  pcSync.startBackgroundSync();
  // Audiobooks play through media_kit on Windows.
  JustAudioMediaKit.title = 'Chapterly';
  JustAudioMediaKit.ensureInitialized();
  const audioFiles = WindowsAudioFiles();
  Listening.files = audioFiles;
  final listenController = ListenController(
    repository: repository,
    library: await AudioLibrary.load(
      File(p.join(dataDir.path, 'audio_library.json')),
    ),
    files: audioFiles,
  );
  Listening.controller = listenController;
  listenController.smartRewind = settings.smartRewind;
  settings.addListener(
    () => listenController.smartRewind = settings.smartRewind,
  );
  // The keyboard's media keys and Windows' media pop-up.
  final mediaControls = SystemMediaControls(listenController);
  MediaControlsHolder.controls = mediaControls;
  unawaited(mediaControls.start());
  // Audiobook bookmarks live with the books (and sync). Bookmarks from
  // before 1.11.0 are moved over from their old file, once.
  AudioBookmarking.repository = repository;
  if (!settings.bookmarksMoved) {
    await moveOldBookmarks(
      File(p.join(dataDir.path, 'audio_bookmarks.json')),
      repository,
    );
    settings.markBookmarksMoved();
  }
  // The reader: which book file belongs to which book on this PC, and the
  // folder with Chapterly's copies of the files.
  EbookReading.library = await EbookLibrary.load(
    File(p.join(dataDir.path, 'ebook_library.json')),
  );
  EbookReading.files = const WindowsEbookFiles();
  EbookReading.repository = repository;
  EbookReading.booksDir = Directory(p.join(dataDir.path, 'books'));
  // The book server: browsing it, downloads, and keeping your place in its
  // books the same on every device.
  await _setUpBookServer(dataDir, repository, listenController, settings);
  // Links the files in your book and audiobook folders to your books.
  LibraryScanning.scanner = LibraryScanner(
    repository: repository,
    ebookLibrary: EbookReading.library!,
    ebookFiles: EbookReading.files!,
    booksDir: EbookReading.booksDir!,
    audioFiles: audioFiles,
    audioLibrary: listenController.library,
    memory: await ScanMemory.load(
      File(p.join(dataDir.path, 'scan_state.json')),
    ),
    closePlayerFor: (bookId) async {
      if (listenController.bookId == bookId) await listenController.close();
    },
  );
  WidgetsBinding.instance.addObserver(
    AutoBackupObserver(repository: repository, settings: settings),
  );
  // Not awaited: the app opens while the backup is written.
  runAutoBackup(repository, settings);
  // The daily reading reminder: on the PC it shows in the app.
  _remindNowAndThen(repository, settings);
  // Closing the window can keep Chapterly in the tray (a setting).
  unawaited(AppTray(settings).start());
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

/// Shows the reading reminder once a day after its time, while Chapterly
/// is open, when you're behind this year's goal.
void _remindNowAndThen(BookRepository repository, AppSettings settings) {
  void check() {
    if (!settings.reminderOn) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final shown = settings.reminderShownOn;
    if (shown != null && !shown.isBefore(today)) return;
    if (now.hour * 60 + now.minute < settings.reminderMinutes) return;
    final text = reminderText(
      repository.books,
      goal: settings.goalFor(now.year),
      finishDates: [
        for (final book in repository.booksOn(Shelf.inProgress))
          if (forecastFor(book) case final forecast?) forecast.date,
      ],
    );
    if (text == null) return;
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    settings.markReminderShown(today);
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 12),
    ));
  }

  // A moment after start, once the window is up, then now and then.
  Timer(const Duration(seconds: 20), check);
  Timer.periodic(const Duration(minutes: 10), (_) => check());
}

/// Saves your place on the book server and stops the player, before
/// Chapterly restarts with another profile.
Future<void> _beforeRestart() async {
  try {
    await BookServer.sync?.send().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Sent next time this profile opens.
  }
  try {
    await Listening.controller?.close();
  } catch (_) {
    // Already stopped.
  }
}

Future<void> _setUpBookServer(
  Directory dataDir,
  BookRepository repository,
  ListenController listenController,
  AppSettings settings,
) async {
  try {
    final state = await ServerState.load(
      File(p.join(dataDir.path, 'book_server.json')),
      tokens: SecureTokenStore(storageKey: SecureTokenStore.keyFor(_profileId)),
    );
    final sync = ServerSync(
      state: state,
      repository: repository,
      ebooks: EbookReading.library,
      isOpen: (bookId, kind) => kind == 'ebook'
          ? EbookReading.openBookId == bookId
          : listenController.bookId == bookId && listenController.playing,
      onAudioMoved: (bookId, progress) async {
        if (listenController.bookId != bookId) return;
        // Loaded but paused: go to the new place.
        await listenController.seekTo(
          progress.track,
          Duration(milliseconds: progress.trackMs),
        );
      },
    );
    final downloads = ServerDownloads(
      sync: sync,
      repository: repository,
      ebooks: EbookReading.library,
      booksDir: EbookReading.booksDir,
      audio: listenController.library,
      audioFiles: Listening.files,
      audioDir: Directory(p.join(dataDir.path, 'server_audio')),
    );
    BookServer.sync = sync;
    BookServer.downloads = downloads;
    BookServer.library = LibrarySync(
      sync: sync,
      repository: repository,
      settings: settings,
      // Apart from the Wi-Fi sync's, which compares with the phone.
      base: await SyncBase.load(File(p.join(dataDir.path, 'book_server_library.json'))),
    );
    sync.start();
    final observer = _BookServerObserver(sync);
    WidgetsBinding.instance.addObserver(observer);
    // The PC often stays open for hours: sync now and then as well.
    Timer.periodic(const Duration(minutes: 15), (_) => observer.syncSoon());
    unawaited(downloads.cleanUp());
    unawaited(_syncAndTell(sync));
  } catch (_) {
    // No book server this time.
  }
}

/// Syncs, and says so when a book moved on to a place saved elsewhere.
Future<void> _syncAndTell(ServerSync sync) async {
  final text = await BookServer.syncAll();
  if (text == null) return;
  _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
}

/// Syncs your places when Chapterly comes back to the front, and sends them
/// when it goes to the back.
class _BookServerObserver with WidgetsBindingObserver {
  _BookServerObserver(this.sync);

  final ServerSync sync;
  DateTime? _last;

  void syncSoon() {
    final last = _last;
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _last = now;
    unawaited(_syncAndTell(sync));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(sync.send());
    } else if (state == AppLifecycleState.resumed) {
      syncSoon();
    }
  }
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
        scaffoldMessengerKey: _messengerKey,
        navigatorKey: Listening.navigatorKey,
        theme: buildTheme(settings, Brightness.light),
        darkTheme: buildTheme(settings, Brightness.dark),
        themeMode: settings.themeMode,
        // Everything is behind the lock: the mini player, the timer and
        // pasting a cover too.
        builder: (context, child) => LockGate(
          settings: settings,
          child: MiniTimerHost(
            child: MiniPlayerHost(
              child: CoverPasteShortcut(
                repository: repository,
                messengerKey: _messengerKey,
                child: NowPlayingFrame(
                  repository: repository,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        home: HomeShell(
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
