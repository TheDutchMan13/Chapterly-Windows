import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../audio/audio_files.dart';
import '../audio/audio_library.dart';
import '../audio/audio_tags.dart';
import '../ebook/ebook_files.dart';
import '../ebook/ebook_library.dart';
import '../ebook/epub_info.dart';
import '../ebook/pdf_info.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'book_repository.dart';
import 'calibre.dart';
import 'cover_image.dart';
import 'file_match.dart';

// Windows app only: scanning your book and audiobook folders and linking
// what is found to the books in your library.

/// What a scan found: a book file, or an audiobook.
enum ScanKind { book, audiobook }

/// One thing found in a folder: an EPUB or PDF, or an audiobook (a folder of
/// audio files, or a single audio file such as an M4B).
class ScanItem {
  ScanItem({
    required this.kind,
    required this.key,
    required this.name,
    required this.files,
    this.folder = '',
    this.directory = '',
  });

  final ScanKind kind;

  /// Stays the same while the file stays the same (its place, size and
  /// time), so a scan can skip what it has dealt with before.
  final String key;

  /// The file name, or for an audiobook folder the folder's name.
  final String name;
  final List<PickedFile> files;

  /// The folder holding it ("Frank Herbert" for Frank Herbert/Dune/01.mp3).
  /// Helps recognise the author. Empty when it is the scanned folder itself.
  final String folder;

  /// The folder that holds only this item, where a Calibre metadata.opf
  /// and cover.jpg would be. Empty when it shares its folder with others.
  final String directory;

  /// What Calibre knows about it, when it sits in a Calibre book folder.
  CalibreInfo? calibre;

  /// The title and author found inside the file, when it has any.
  String title = '';
  String author = '';

  /// The parts of its name that may be the title or the author.
  List<String> get nameParts => [
        ...fileNameParts(name),
        if (folder.isNotEmpty) folder,
      ];
}

// ---- Which audio files make one audiobook

/// One audiobook found among audio files: a folder, or a single file.
class AudiobookUnit {
  const AudiobookUnit({
    required this.name,
    required this.folder,
    required this.root,
    required this.files,
  });

  /// The folder's name, or the file's name for a single file.
  final String name;

  /// The folder above it, which often names the author.
  final String folder;

  /// The folder that holds the files, relative to the scanned folder (empty
  /// when they sit in it directly), written with "/".
  final String root;

  /// Every audio file, relative to the scanned folder, written with "/".
  final List<String> files;

  /// A file's name inside the audiobook ("CD 1/01.mp3").
  String nameOf(String file) =>
      root.isEmpty ? file : file.substring(root.length + 1);
}

class _Node {
  final files = <String>[];
  final dirs = <String, _Node>{};
}

final _discFolder = RegExp(
  r'^(cd|disc|disk|part|volume|vol)[\s._-]*\d',
  caseSensitive: false,
);

/// Works out which audio files belong to one audiobook, from their paths
/// relative to the scanned folder (written with "/"):
///
/// - audio files sitting directly in a folder are one audiobook named after
///   the folder, together with any "CD 1", "Disc 2" or "Part 3" folders in it;
/// - except that several .m4b files in one folder are separate audiobooks;
/// - audio files directly in the scanned folder are each their own.
List<AudiobookUnit> groupAudiobooks(Iterable<String> relativePaths) {
  final root = _Node();
  for (final path in relativePaths) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty || !isAudioFileName(parts.last)) continue;
    var node = root;
    for (final dir in parts.take(parts.length - 1)) {
      node = node.dirs.putIfAbsent(dir, _Node.new);
    }
    node.files.add(parts.last);
  }

  final units = <AudiobookUnit>[];

  void collect(_Node node, String prefix, List<String> into) {
    for (final file in node.files) {
      into.add(prefix.isEmpty ? file : '$prefix/$file');
    }
    for (final entry in node.dirs.entries) {
      collect(
        entry.value,
        prefix.isEmpty ? entry.key : '$prefix/${entry.key}',
        into,
      );
    }
  }

  void visit(_Node node, List<String> path) {
    final here = path.join('/');
    final discs = [
      for (final name in node.dirs.keys)
        if (_discFolder.hasMatch(name)) name,
    ];
    final isBook = path.isNotEmpty && (node.files.isNotEmpty || discs.isNotEmpty);
    final parent = path.length > 1 ? path[path.length - 2] : '';
    if (path.isEmpty) {
      for (final file in node.files) {
        units.add(AudiobookUnit(name: file, folder: '', root: '', files: [file]));
      }
    } else if (isBook) {
      final separate = discs.isEmpty &&
          node.files.length > 1 &&
          node.files.every((file) => file.toLowerCase().endsWith('.m4b'));
      if (separate) {
        for (final file in node.files) {
          units.add(AudiobookUnit(
            name: file,
            folder: path.last,
            root: here,
            files: ['$here/$file'],
          ));
        }
      } else {
        final files = [for (final file in node.files) '$here/$file'];
        for (final disc in discs) {
          collect(node.dirs[disc]!, '$here/$disc', files);
        }
        units.add(AudiobookUnit(
          name: path.last,
          folder: parent,
          root: here,
          files: files,
        ));
      }
    }
    for (final entry in node.dirs.entries) {
      if (isBook && discs.contains(entry.key)) continue;
      visit(entry.value, [...path, entry.key]);
    }
  }

  visit(root, const []);
  return units;
}

// ---- Deciding what to do with each thing found

/// What a scan does with one thing it found.
enum ScanOutcome {
  /// A clear match with a book that has no such file yet: link it.
  link,

  /// A clear match, but the book already has a file of this kind. Left alone.
  alreadyLinked,

  /// A clear match, but another file in this scan was linked to the book.
  duplicate,

  /// Not sure which book it is, or none matches: you decide.
  review,
}

class ScanDecision {
  const ScanDecision(
    this.item,
    this.outcome, {
    this.book,
    this.matches = const [],
  });

  final ScanItem item;
  final ScanOutcome outcome;

  /// The book to link to (for link, alreadyLinked and duplicate).
  final Book? book;

  /// The likely books, best first.
  final List<BookMatch> matches;
}

/// Decides what to do with each of [items], whose [ScanItem.title] and
/// [ScanItem.author] are already filled in. [hasLink] says whether a book
/// already has a file of that kind. Only a clear match is linked, a file is
/// never put over one that is already linked, and a book gets at most one
/// file of each kind in one scan.
List<ScanDecision> planScan(
  List<ScanItem> items,
  List<Book> books, {
  required bool Function(ScanKind kind, String bookId) hasLink,
}) {
  final claimed = <String>{};
  final decisions = <ScanDecision>[];
  for (final item in items) {
    final matches = findMatchingBooks(
      books,
      title: item.title,
      author: item.author,
      nameParts: item.nameParts,
    );
    if (!isSureMatch(matches)) {
      decisions.add(ScanDecision(item, ScanOutcome.review, matches: matches));
      continue;
    }
    final book = matches.first.book;
    final ScanOutcome outcome;
    if (hasLink(item.kind, book.id)) {
      outcome = ScanOutcome.alreadyLinked;
    } else if (!claimed.add('${item.kind.name}|${book.id}')) {
      outcome = ScanOutcome.duplicate;
    } else {
      outcome = ScanOutcome.link;
    }
    decisions.add(ScanDecision(item, outcome, book: book, matches: matches));
  }
  return decisions;
}

// ---- Looking in the folders

/// Book files bigger than this are matched by their file name only.
const _readLimit = 64 * 1024 * 1024;

/// What a scan has dealt with before, kept in a small file, so a scan only
/// looks at new or changed files. A file you linked, skipped, or that was
/// already linked is not looked at again (so a link you remove stays removed).
class ScanMemory {
  ScanMemory({this.file});

  final File? file;

  /// Keys of files that are dealt with.
  final settled = <String>{};

  /// Keys of files already shown to you in a message, so that opening
  /// Chapterly does not mention the same ones every time.
  final reported = <String>{};

  static Future<ScanMemory> load(File file) async {
    final memory = ScanMemory(file: file);
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          for (final entry in [
            (json['settled'], memory.settled),
            (json['reported'], memory.reported),
          ]) {
            final list = entry.$1;
            if (list is List) {
              entry.$2.addAll(list.whereType<String>());
            }
          }
        }
      }
    } catch (_) {
      // Unreadable: start again; the worst case is a file looked at twice.
    }
    return memory;
  }

  Future<void> save() async {
    final target = file;
    if (target == null) return;
    try {
      await target.writeAsString(jsonEncode({
        'settled': settled.toList(),
        'reported': reported.toList(),
      }));
    } catch (_) {
      // Not saved; the next scan looks at those files again.
    }
  }
}

/// The EPUB and PDF files in [folder] and its subfolders that are not in
/// [settled].
Future<List<ScanItem>> findBookFiles(String folder, Set<String> settled) async {
  final items = <ScanItem>[];
  try {
    await for (final entity
        in Directory(folder).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (ebookFormatOf(name) == null) continue;
      final FileStat stat;
      try {
        stat = await entity.stat();
      } catch (_) {
        continue;
      }
      final key = 'book|${entity.path}|${stat.size}|'
          '${stat.modified.millisecondsSinceEpoch}';
      if (settled.contains(key)) continue;
      final parent = p.dirname(entity.path);
      items.add(ScanItem(
        kind: ScanKind.book,
        key: key,
        name: name,
        folder: p.equals(parent, folder) ? '' : p.basename(parent),
        directory: p.equals(parent, folder) ? '' : parent,
        files: [PickedFile(location: entity.path, name: name)],
      ));
    }
  } catch (_) {
    // A folder that cannot be read: what was found so far is used.
  }
  return items;
}

/// The audiobooks in [folder] and its subfolders that are not in [settled].
Future<List<ScanItem>> findAudiobooks(
  String folder,
  Set<String> settled,
) async {
  final stats = <String, FileStat>{};
  final relative = <String>[];
  try {
    await for (final entity
        in Directory(folder).list(recursive: true, followLinks: false)) {
      if (entity is! File || !isAudioFileName(entity.path)) continue;
      final path = p.relative(entity.path, from: folder).replaceAll('\\', '/');
      relative.add(path);
      try {
        stats[path] = await entity.stat();
      } catch (_) {
        // Its size and time are left out of the key.
      }
    }
  } catch (_) {
    // A folder that cannot be read: what was found so far is used.
  }
  final items = <ScanItem>[];
  final units = groupAudiobooks(relative);
  final perRoot = <String, int>{};
  for (final unit in units) {
    perRoot[unit.root] = (perRoot[unit.root] ?? 0) + 1;
  }
  for (final unit in units) {
    final files = [...unit.files]..sort();
    var bytes = 0;
    var newest = 0;
    for (final file in files) {
      final stat = stats[file];
      if (stat == null) continue;
      bytes += stat.size;
      final time = stat.modified.millisecondsSinceEpoch;
      if (time > newest) newest = time;
    }
    final key = 'audio|${p.join(folder, files.first)}|${files.length}|'
        '$bytes|$newest';
    if (settled.contains(key)) continue;
    items.add(ScanItem(
      kind: ScanKind.audiobook,
      key: key,
      name: unit.name,
      folder: unit.folder,
      directory: unit.root.isEmpty || perRoot[unit.root] != 1
          ? ''
          : p.join(folder, unit.root),
      files: [
        for (final file in files)
          PickedFile(location: p.join(folder, file), name: unit.nameOf(file)),
      ],
    ));
  }
  return items;
}

/// Fills in the title and author found inside the item's file.
Future<void> readScanInfo(ScanItem item, AudioFiles audioFiles) async {
  try {
    // Calibre's details are the best source: no need to open the file.
    if (item.directory.isNotEmpty) {
      final calibre = await readCalibreFolder(item.directory);
      if (calibre != null) {
        item.calibre = calibre;
        item.title = calibre.title;
        item.author = calibre.author;
        if (item.author.isNotEmpty) return;
      }
    }
    if (item.kind == ScanKind.book) {
      final file = File(item.files.first.location);
      if (await file.length() > _readLimit) return;
      final bytes = await file.readAsBytes();
      final info = ebookFormatOf(item.name) == EbookFormat.epub
          ? epubTitleAndAuthor(bytes)
          : pdfTitleAndAuthor(bytes);
      if (info != null) {
        if (item.title.isEmpty) item.title = info.title;
        item.author = info.author;
      }
      return;
    }
    final first = [...item.files]
      ..sort((a, b) => naturalCompare(a.name, b.name));
    final source = audioFiles.open(first.first.location);
    try {
      final tags = await readAudioTags(source);
      // With one file per chapter the title is only the chapter's.
      if (item.title.isEmpty) {
        item.title =
            item.files.length > 1 && tags.album.isEmpty ? '' : tags.bookTitle;
      }
      item.author = tags.author;
    } finally {
      await source.close();
    }
  } catch (_) {
    // Nothing inside it could be read; its name is used.
  }
}

// ---- The scan itself

/// What one scan did.
class ScanResult {
  const ScanResult({
    this.linkedBooks = 0,
    this.linkedAudiobooks = 0,
    this.looked = 0,
    this.review = const [],
    this.newUnsure = 0,
    this.problems = const [],
    this.filledDetails = 0,
  });

  final int linkedBooks;
  final int linkedAudiobooks;

  /// New or changed files looked at.
  final int looked;

  /// Files left for you to decide on.
  final List<ScanDecision> review;

  /// Of those, ones with a likely book that were not shown to you before.
  final int newUnsure;

  final List<String> problems;

  /// Books that got a cover or other details from Calibre.
  final int filledDetails;

  int get linked => linkedBooks + linkedAudiobooks;
}

/// Links the book files and audiobooks in your folders to the books in your
/// library. Only clear matches are linked by themselves; the rest is kept in
/// [pending] for you to look through.
class LibraryScanner extends ChangeNotifier {
  LibraryScanner({
    required this.repository,
    required this.ebookLibrary,
    required this.ebookFiles,
    required this.booksDir,
    required this.audioFiles,
    required this.audioLibrary,
    required this.memory,
    this.closePlayerFor,
  });

  final BookRepository repository;
  final EbookLibrary ebookLibrary;
  final EbookFiles ebookFiles;
  final Directory booksDir;
  final AudioFiles audioFiles;
  final AudioLibrary audioLibrary;
  final ScanMemory memory;

  /// Called before an audiobook is put over another one, so the player lets
  /// go of the old files.
  final Future<void> Function(String bookId)? closePlayerFor;

  bool _running = false;
  int _done = 0;
  int _total = 0;
  String _current = '';
  int _filled = 0;
  String _message = '';
  List<ScanDecision> _pending = const [];

  bool get running => _running;

  /// What the scan is doing now.
  String get message => _message;

  /// 0.0 to 1.0 for the step that is running, or null when the amount of
  /// work is not known yet.
  double? get progress => _total <= 0 ? null : _done / _total;

  /// The file or book being worked on.
  String get current => _current;

  /// Files from the last scan that wait for you.
  List<ScanDecision> get pending => List.unmodifiable(_pending);

  bool hasLink(ScanKind kind, String bookId) => kind == ScanKind.book
      ? ebookLibrary.linkFor(bookId) != null
      : audioLibrary.linkFor(bookId) != null;

  /// Looks in the folders (either may be null) and links what is clear.
  /// Null when a scan is already running.
  Future<ScanResult?> scan({
    String? booksFolder,
    String? audiobooksFolder,
  }) async {
    if (_running) return null;
    _running = true;
    _filled = 0;
    _message = 'Looking for files...';
    notifyListeners();
    try {
      final items = <ScanItem>[
        if (booksFolder != null && booksFolder.isNotEmpty)
          ...await findBookFiles(booksFolder, memory.settled),
        if (audiobooksFolder != null && audiobooksFolder.isNotEmpty)
          ...await findAudiobooks(audiobooksFolder, memory.settled),
      ];
      var done = 0;
      for (final item in items) {
        done++;
        _message = 'Reading $done of ${items.length}...';
        _done = done;
        _total = items.length;
        _current = item.name;
        notifyListeners();
        await readScanInfo(item, audioFiles);
        // Let the app draw between files.
        await Future<void>.delayed(Duration.zero);
      }
      final decisions = planScan(
        items,
        repository.books,
        hasLink: hasLink,
      );
      _done = 0;
      _total = decisions.length;
      var books = 0;
      var audiobooks = 0;
      final problems = <String>[];
      final review = <ScanDecision>[];
      for (final decision in decisions) {
        _done++;
        _current = decision.item.name;
        switch (decision.outcome) {
          case ScanOutcome.link:
            _message = 'Linking ${decision.item.name}...';
            notifyListeners();
            final problem = await linkToBook(decision.item, decision.book!.id);
            if (problem != null) {
              problems.add(problem);
            } else {
              memory.settled.add(decision.item.key);
              if (decision.item.kind == ScanKind.book) {
                books++;
              } else {
                audiobooks++;
              }
            }
          case ScanOutcome.alreadyLinked || ScanOutcome.duplicate:
            memory.settled.add(decision.item.key);
          case ScanOutcome.review:
            review.add(decision);
        }
        await Future<void>.delayed(Duration.zero);
      }
      final fresh = review
          .where((d) =>
              d.matches.isNotEmpty && !memory.reported.contains(d.item.key))
          .length;
      memory.reported.addAll(review.map((d) => d.item.key));
      await memory.save();
      _pending = review;
      return ScanResult(
        linkedBooks: books,
        linkedAudiobooks: audiobooks,
        looked: items.length,
        review: review,
        newUnsure: fresh,
        problems: problems,
        filledDetails: _filled,
      );
    } finally {
      _running = false;
      _message = '';
      _done = 0;
      _total = 0;
      _current = '';
      notifyListeners();
    }
  }

  /// Links the item to the book. Returns a problem to show, or null.
  Future<String?> linkToBook(ScanItem item, String bookId) async {
    final problem = await _link(item, bookId);
    final calibre = item.calibre;
    if (problem == null && calibre != null) {
      try {
        if (await fillFromCalibre(repository, bookId, calibre)) _filled++;
      } catch (_) {
        // The details are a bonus; the link is already made.
      }
    }
    return problem;
  }

  Future<String?> _link(ScanItem item, String bookId) async {
    try {
      if (item.kind == ScanKind.book) {
        return await addBookFile(
          library: ebookLibrary,
          files: ebookFiles,
          booksDir: booksDir,
          bookId: bookId,
          picked: item.files.first,
        );
      }
      final link = await buildAudioLink(audioFiles, item.files);
      if (link == null) return 'There are no audio files in "${item.name}".';
      if (audioLibrary.linkFor(bookId) != null) {
        await closePlayerFor?.call(bookId);
      }
      await audioLibrary.setLink(bookId, link);
      final book = repository.byId(bookId);
      if (book != null && book.format == null) {
        await repository.setFormat(bookId, BookFormat.audiobook);
      }
      return null;
    } catch (_) {
      return 'Could not link "${item.name}".';
    }
  }

  /// Adds a new book and links the item to it. Returns a problem or null.
  Future<String?> linkToNewBook(
    ScanItem item, {
    required String title,
    required String author,
    required Shelf shelf,
  }) async {
    await repository.add(
      title: title,
      author: author,
      shelf: shelf,
      format: item.kind == ScanKind.book
          ? BookFormat.ebook
          : BookFormat.audiobook,
    );
    // A new book goes first in the list.
    final added = repository.allBooks.firstOrNull;
    if (added == null || added.title != title) {
      return 'The book could not be added.';
    }
    return linkToBook(item, added.id);
  }

  /// Linking a pending item to a book, from the review: when it worked the
  /// item is settled and leaves the list.
  Future<String?> resolveWithBook(ScanItem item, String bookId) async {
    final problem = await linkToBook(item, bookId);
    if (problem == null) await _settle(item);
    return problem;
  }

  Future<String?> resolveWithNewBook(
    ScanItem item, {
    required String title,
    required String author,
    required Shelf shelf,
  }) async {
    final problem = await linkToNewBook(
      item,
      title: title,
      author: author,
      shelf: shelf,
    );
    if (problem == null) await _settle(item);
    return problem;
  }

  // ---- Importing from a Calibre library

  /// Looks through a Calibre library and says what an import would do.
  /// Null when a scan or import is already running.
  Future<List<CalibrePlanEntry>?> planCalibre(String folder) async {
    if (_running) return null;
    _running = true;
    _message = 'Reading the Calibre library...';
    notifyListeners();
    try {
      final found = await findCalibreBooks(folder);
      return planCalibreImport(found, repository.books);
    } finally {
      _running = false;
      _message = '';
      _done = 0;
      _total = 0;
      _current = '';
      notifyListeners();
    }
  }

  /// Adds the books of [plan] that are not in your library (on [shelf], with
  /// their Calibre details and cover, and with their files linked when
  /// [linkFiles] is true) and fills blank details of the ones you have.
  Future<CalibreImportResult?> importCalibre(
    List<CalibrePlanEntry> plan, {
    required Shelf shelf,
    required bool linkFiles,
  }) async {
    if (_running) return null;
    _running = true;
    var added = 0;
    var filled = 0;
    var linked = 0;
    final problems = <String>[];
    try {
      var done = 0;
      for (final entry in plan) {
        done++;
        _message = 'Importing $done of ${plan.length}...';
        _done = done;
        _total = plan.length;
        _current = entry.book.info.title;
        notifyListeners();
        final info = entry.book.info;
        if (entry.outcome == CalibreOutcome.fill && entry.match != null) {
          if (await fillFromCalibre(repository, entry.match!.id, info)) {
            filled++;
          }
        } else if (entry.outcome == CalibreOutcome.add) {
          final id = newBookId();
          final hasEbook = entry.book.bookFiles.isNotEmpty;
          final hasAudio = entry.book.audioFiles.isNotEmpty;
          String? cover;
          final coverPath = info.coverPath;
          if (coverPath != null) {
            try {
              cover = await makeDataCover(await File(coverPath).readAsBytes());
            } catch (_) {
              cover = null;
            }
          }
          final count = await repository.importBooks([
            Book(
              id: id,
              title: info.title,
              author: info.author,
              shelf: shelf,
              addedAt: DateTime.now(),
              tags: info.tags,
              isbn: info.isbn,
              coverUrl: cover,
              firstPublishYear: info.year,
              series: info.series,
              seriesNumber: info.seriesNumber,
              format: hasEbook
                  ? BookFormat.ebook
                  : (hasAudio ? BookFormat.audiobook : null),
            ),
          ]);
          if (count > 0) {
            added++;
            if (linkFiles) {
              if (hasEbook) {
                final file = entry.book.bookFiles.first;
                final name = p.basename(file);
                final problem = await _link(
                  ScanItem(
                    kind: ScanKind.book,
                    key: 'book|$file',
                    name: name,
                    files: [PickedFile(location: file, name: name)],
                  ),
                  id,
                );
                if (problem == null) {
                  linked++;
                } else {
                  problems.add(problem);
                }
              }
              if (hasAudio) {
                final problem = await _link(
                  ScanItem(
                    kind: ScanKind.audiobook,
                    key: 'audio|${entry.book.directory}',
                    name: p.basename(entry.book.directory),
                    files: [
                      for (final file in entry.book.audioFiles)
                        PickedFile(
                          location: file,
                          name: p.relative(file, from: entry.book.directory),
                        ),
                    ],
                  ),
                  id,
                );
                if (problem == null) {
                  linked++;
                } else {
                  problems.add(problem);
                }
              }
            }
          }
        }
        await Future<void>.delayed(Duration.zero);
      }
      return CalibreImportResult(
        added: added,
        filled: filled,
        linked: linked,
        unsure: plan.where((e) => e.outcome == CalibreOutcome.unsure).length,
        problems: problems,
      );
    } finally {
      _running = false;
      _message = '';
      _done = 0;
      _total = 0;
      _current = '';
      notifyListeners();
    }
  }

  /// Leaves the item alone from now on (until the file changes).
  Future<void> skip(ScanItem item) => _settle(item);

  Future<void> skipAll() async {
    for (final decision in _pending) {
      memory.settled.add(decision.item.key);
    }
    _pending = const [];
    await memory.save();
    notifyListeners();
  }

  Future<void> _settle(ScanItem item) async {
    memory.settled.add(item.key);
    _pending = [
      for (final decision in _pending)
        if (decision.item.key != item.key) decision,
    ];
    await memory.save();
    notifyListeners();
  }
}

/// What a Calibre import did.
class CalibreImportResult {
  const CalibreImportResult({
    required this.added,
    required this.filled,
    required this.linked,
    required this.unsure,
    this.problems = const [],
  });

  final int added;

  /// Books you already had that got blank details filled in.
  final int filled;

  /// Book files and audiobooks linked to the added books.
  final int linked;

  /// Calibre books that might be ones you have: left alone.
  final int unsure;
  final List<String> problems;
}

/// The scanner for the whole app, set up in main.dart. Null in tests and
/// until set up, and the folder scan then stays hidden.
class LibraryScanning {
  LibraryScanning._();

  static LibraryScanner? scanner;
}
