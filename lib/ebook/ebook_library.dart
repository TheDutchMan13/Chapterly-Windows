import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The kinds of book file the reader opens.
enum EbookFormat { epub, pdf }

extension EbookFormatLabel on EbookFormat {
  String get label => switch (this) {
        EbookFormat.epub => 'EPUB',
        EbookFormat.pdf => 'PDF',
      };

  String get fileExtension => switch (this) {
        EbookFormat.epub => 'epub',
        EbookFormat.pdf => 'pdf',
      };
}

/// The format of a file going by its name, or null when the reader cannot
/// open it.
EbookFormat? ebookFormatOf(String fileName) {
  final name = fileName.toLowerCase().trim();
  if (name.endsWith('.epub')) return EbookFormat.epub;
  if (name.endsWith('.pdf')) return EbookFormat.pdf;
  return null;
}

/// "1.2 MB" and the like.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

double _fraction(Object? value) {
  if (value is! num) return 0;
  final v = value.toDouble();
  if (v.isNaN) return 0;
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

/// Where you are in a book file: an EPUB location (CFI) or a PDF page
/// number, and how far through the book that is.
@immutable
class EbookPosition {
  const EbookPosition({
    required this.locator,
    required this.progress,
    this.chapter,
  });

  /// An EPUB CFI, or the page number of a PDF as text.
  final String locator;

  /// From 0 to 1.
  final double progress;

  /// The chapter's title, when known.
  final String? chapter;

  Map<String, Object?> toJson() => {
        'locator': locator,
        'progress': progress,
        if (chapter != null) 'chapter': chapter,
      };

  static EbookPosition? fromJson(Object? value) {
    if (value is! Map) return null;
    final locator = value['locator'];
    if (locator is! String || locator.isEmpty) return null;
    final chapter = value['chapter'];
    return EbookPosition(
      locator: locator,
      progress: _fraction(value['progress']),
      chapter: chapter is String && chapter.isNotEmpty ? chapter : null,
    );
  }
}

/// A place in the book you want to find again.
@immutable
class EbookBookmark {
  const EbookBookmark({
    required this.locator,
    required this.progress,
    required this.label,
    required this.addedAt,
  });

  final String locator;
  final double progress;

  /// The chapter or page, to show in the list.
  final String label;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
        'locator': locator,
        'progress': progress,
        'label': label,
        'addedAt': addedAt.toIso8601String(),
      };

  static EbookBookmark? fromJson(Object? value) {
    if (value is! Map) return null;
    final locator = value['locator'];
    if (locator is! String || locator.isEmpty) return null;
    final label = value['label'];
    return EbookBookmark(
      locator: locator,
      progress: _fraction(value['progress']),
      label: label is String ? label : '',
      addedAt: _date(value['addedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// The colours a highlight can have.
enum HighlightColour { yellow, green, blue, pink }

extension HighlightColourLabel on HighlightColour {
  String get label => switch (this) {
        HighlightColour.yellow => 'Yellow',
        HighlightColour.green => 'Green',
        HighlightColour.blue => 'Blue',
        HighlightColour.pink => 'Pink',
      };
}

/// A passage you marked in a book. It is also saved as a quote on the
/// book.
@immutable
class EbookHighlight {
  const EbookHighlight({
    required this.locator,
    required this.text,
    required this.addedAt,
    this.colour = HighlightColour.yellow,
    this.note,
  });

  /// Where the passage is: a CFI range on Android, a range of the chapter's
  /// text on Windows.
  final String locator;
  final String text;
  final DateTime addedAt;
  final HighlightColour colour;

  /// Your own words about the passage, if any.
  final String? note;

  EbookHighlight copyWith({
    HighlightColour? colour,
    String? Function()? note,
  }) =>
      EbookHighlight(
        locator: locator,
        text: text,
        addedAt: addedAt,
        colour: colour ?? this.colour,
        note: note == null ? this.note : note(),
      );

  Map<String, Object?> toJson() => {
        'locator': locator,
        'text': text,
        'addedAt': addedAt.toIso8601String(),
        if (colour != HighlightColour.yellow) 'colour': colour.name,
        if (note != null) 'note': note,
      };

  static EbookHighlight? fromJson(Object? value) {
    if (value is! Map) return null;
    final locator = value['locator'];
    final text = value['text'];
    if (locator is! String || locator.isEmpty || text is! String) return null;
    final note = value['note'];
    return EbookHighlight(
      locator: locator,
      text: text,
      addedAt: _date(value['addedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      colour: HighlightColour.values.asNameMap()[value['colour']] ??
          HighlightColour.yellow,
      note: note is String && note.trim().isNotEmpty ? note : null,
    );
  }
}

/// Time spent in the reader with a book on one day, and how much of the
/// book you got through.
@immutable
class EbookDay {
  const EbookDay({
    required this.day,
    required this.minutes,
    required this.progress,
  });

  /// Midnight of the day.
  final DateTime day;
  final int minutes;

  /// The share of the book read, from 0 to 1. Going back does not count.
  final double progress;

  Map<String, Object?> toJson() => {
        'day': day.toIso8601String(),
        'minutes': minutes,
        'progress': progress,
      };

  static EbookDay? fromJson(Object? value) {
    if (value is! Map) return null;
    final day = _date(value['day']);
    final minutes = value['minutes'];
    if (day == null || minutes is! int || minutes < 0) return null;
    return EbookDay(
      day: day,
      minutes: minutes,
      progress: _fraction(value['progress']),
    );
  }
}

/// A book's file on this device: a copy Chapterly keeps in its own folder,
/// so it still opens if the original is moved or deleted.
@immutable
class EbookLink {
  const EbookLink({
    required this.path,
    required this.name,
    required this.bytes,
    required this.format,
    required this.addedAt,
    this.position,
    this.bookmarks = const [],
    this.highlights = const [],
    this.pageCount,
    this.prefs,
    this.days = const [],
  });

  /// Where Chapterly's copy is.
  final String path;

  /// The name of the file you picked.
  final String name;
  final int bytes;
  final EbookFormat format;
  final DateTime addedAt;
  final EbookPosition? position;
  final List<EbookBookmark> bookmarks;
  final List<EbookHighlight> highlights;

  /// For a PDF, its number of pages once the reader has opened it.
  final int? pageCount;

  /// The book's own text settings, or null to use the usual ones. Only the
  /// look of the text is taken from here (see [ReaderPrefs.withLookOf]).
  final ReaderPrefs? prefs;

  /// Time in the reader, one entry per day, oldest first.
  final List<EbookDay> days;

  EbookLink copyWith({
    EbookPosition? Function()? position,
    List<EbookBookmark>? bookmarks,
    List<EbookHighlight>? highlights,
    int? Function()? pageCount,
    ReaderPrefs? Function()? prefs,
    List<EbookDay>? days,
  }) =>
      EbookLink(
        path: path,
        name: name,
        bytes: bytes,
        format: format,
        addedAt: addedAt,
        position: position == null ? this.position : position(),
        bookmarks: bookmarks ?? this.bookmarks,
        highlights: highlights ?? this.highlights,
        pageCount: pageCount == null ? this.pageCount : pageCount(),
        prefs: prefs == null ? this.prefs : prefs(),
        days: days ?? this.days,
      );

  Map<String, Object?> toJson() => {
        'path': path,
        'name': name,
        'bytes': bytes,
        'format': format.name,
        'addedAt': addedAt.toIso8601String(),
        if (position != null) 'position': position!.toJson(),
        if (bookmarks.isNotEmpty)
          'bookmarks': [for (final b in bookmarks) b.toJson()],
        if (highlights.isNotEmpty)
          'highlights': [for (final h in highlights) h.toJson()],
        if (pageCount != null) 'pageCount': pageCount,
        if (prefs != null) 'prefs': prefs!.toJson(),
        if (days.isNotEmpty) 'days': [for (final d in days) d.toJson()],
      };

  static EbookLink? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    final name = value['name'];
    final format = EbookFormat.values.asNameMap()[value['format']];
    if (path is! String || path.isEmpty || name is! String || format == null) {
      return null;
    }
    final bytes = value['bytes'];
    final pageCount = value['pageCount'];
    final bookmarks = value['bookmarks'];
    final highlights = value['highlights'];
    final days = value['days'];
    return EbookLink(
      path: path,
      name: name,
      bytes: bytes is int && bytes >= 0 ? bytes : 0,
      format: format,
      addedAt: _date(value['addedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      position: EbookPosition.fromJson(value['position']),
      bookmarks: [
        if (bookmarks is List)
          for (final item in bookmarks) ?EbookBookmark.fromJson(item),
      ],
      highlights: [
        if (highlights is List)
          for (final item in highlights) ?EbookHighlight.fromJson(item),
      ],
      pageCount: pageCount is int && pageCount > 0 ? pageCount : null,
      prefs: value['prefs'] is Map ? ReaderPrefs.fromJson(value['prefs']) : null,
      days: [
        if (days is List)
          for (final item in days) ?EbookDay.fromJson(item),
      ],
    );
  }
}

/// The reader's colours.
enum ReaderTheme { paper, white, dark, black }

/// The reader's typeface.
enum ReaderFont { serif, sans }

/// Space between lines and around the text.
enum ReaderSpacing { small, normal, large }

/// How the text is shown and how you get to the next page, and a few
/// settings for this device. A book can have its own look (see
/// [EbookLink.prefs]); the device settings are the same for every book.
@immutable
class ReaderPrefs {
  const ReaderPrefs({
    this.fontSize = 18,
    this.theme = ReaderTheme.paper,
    this.font = ReaderFont.serif,
    this.lineSpacing = ReaderSpacing.normal,
    this.margins = ReaderSpacing.normal,
    this.scroll = false,
    this.pageView = false,
    this.keepScreenOn = true,
    this.volumeKeys = true,
    this.brightness,
    this.speechRate = 1.0,
  });

  static const minFontSize = 12;
  static const maxFontSize = 32;
  static const minSpeechRate = 0.5;
  static const maxSpeechRate = 2.0;

  final int fontSize;
  final ReaderTheme theme;
  final ReaderFont font;
  final ReaderSpacing lineSpacing;
  final ReaderSpacing margins;

  /// Android: scroll through the text instead of turning pages.
  final bool scroll;

  /// Windows: show the text a page at a time instead of scrolling.
  final bool pageView;

  /// Android: the screen stays on while the reader is open.
  final bool keepScreenOn;

  /// Android: the volume buttons turn the pages.
  final bool volumeKeys;

  /// Android: the screen brightness in the reader, from 0 to 1, or null
  /// for the phone's own.
  final double? brightness;

  /// How fast the book is read aloud: 1 is normal.
  final double speechRate;

  ReaderPrefs copyWith({
    int? fontSize,
    ReaderTheme? theme,
    ReaderFont? font,
    ReaderSpacing? lineSpacing,
    ReaderSpacing? margins,
    bool? scroll,
    bool? pageView,
    bool? keepScreenOn,
    bool? volumeKeys,
    double? Function()? brightness,
    double? speechRate,
  }) {
    var size = fontSize ?? this.fontSize;
    if (size < minFontSize) size = minFontSize;
    if (size > maxFontSize) size = maxFontSize;
    var light = brightness == null ? this.brightness : brightness();
    if (light != null) {
      light = light.isNaN ? null : light.clamp(0.02, 1.0);
    }
    var rate = speechRate ?? this.speechRate;
    if (rate.isNaN) rate = 1.0;
    rate = rate.clamp(minSpeechRate, maxSpeechRate);
    return ReaderPrefs(
      fontSize: size,
      theme: theme ?? this.theme,
      font: font ?? this.font,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      margins: margins ?? this.margins,
      scroll: scroll ?? this.scroll,
      pageView: pageView ?? this.pageView,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      volumeKeys: volumeKeys ?? this.volumeKeys,
      brightness: light,
      speechRate: rate,
    );
  }

  /// These settings with the look of the text (size, theme, typeface,
  /// spacing, margins and how pages turn) taken from [other].
  ReaderPrefs withLookOf(ReaderPrefs other) => copyWith(
        fontSize: other.fontSize,
        theme: other.theme,
        font: other.font,
        lineSpacing: other.lineSpacing,
        margins: other.margins,
        scroll: other.scroll,
        pageView: other.pageView,
      );

  Map<String, Object?> toJson() => {
        'fontSize': fontSize,
        'theme': theme.name,
        'font': font.name,
        'lineSpacing': lineSpacing.name,
        'margins': margins.name,
        'scroll': scroll,
        'pageView': pageView,
        'keepScreenOn': keepScreenOn,
        'volumeKeys': volumeKeys,
        if (brightness != null) 'brightness': brightness,
        'speechRate': speechRate,
      };

  static ReaderPrefs fromJson(Object? value) {
    if (value is! Map) return const ReaderPrefs();
    final size = value['fontSize'];
    bool? flag(String key) => value[key] is bool ? value[key] as bool : null;
    final light = value['brightness'];
    final rate = value['speechRate'];
    return const ReaderPrefs().copyWith(
      fontSize: size is int ? size : null,
      theme: ReaderTheme.values.asNameMap()[value['theme']],
      font: ReaderFont.values.asNameMap()[value['font']],
      lineSpacing: ReaderSpacing.values.asNameMap()[value['lineSpacing']],
      margins: ReaderSpacing.values.asNameMap()[value['margins']],
      scroll: flag('scroll'),
      pageView: flag('pageView'),
      keepScreenOn: flag('keepScreenOn'),
      volumeKeys: flag('volumeKeys'),
      brightness: () => light is num ? light.toDouble() : null,
      speechRate: rate is num ? rate.toDouble() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.fontSize == fontSize &&
      other.theme == theme &&
      other.font == font &&
      other.lineSpacing == lineSpacing &&
      other.margins == margins &&
      other.scroll == scroll &&
      other.pageView == pageView &&
      other.keepScreenOn == keepScreenOn &&
      other.volumeKeys == volumeKeys &&
      other.brightness == brightness &&
      other.speechRate == speechRate;

  @override
  int get hashCode => Object.hash(
        fontSize,
        theme,
        font,
        lineSpacing,
        margins,
        scroll,
        pageView,
        keepScreenOn,
        volumeKeys,
        brightness,
        speechRate,
      );
}

/// Which book file belongs to which book on this device, where you are in
/// it, your bookmarks and highlights, and the reader's settings. Kept in a
/// file next to the database. It never syncs and is not in backups: the
/// files are on this device only. The book's current page (which the
/// reader keeps up to date) does sync.
class EbookLibrary extends ChangeNotifier {
  EbookLibrary({this.file});

  /// Where it is saved, or null to keep it in memory only (tests).
  final File? file;
  final _links = <String, EbookLink>{};
  ReaderPrefs _prefs = const ReaderPrefs();

  static Future<EbookLibrary> load(File file) async {
    final library = EbookLibrary(file: file);
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          final links = data['links'];
          if (links is Map) {
            for (final entry in links.entries) {
              final link = EbookLink.fromJson(entry.value);
              if (link != null) library._links[entry.key.toString()] = link;
            }
          }
          library._prefs = ReaderPrefs.fromJson(data['prefs']);
        }
      }
    } catch (_) {
      // A damaged file only loses the links; the books are untouched.
    }
    return library;
  }

  EbookLink? linkFor(String bookId) => _links[bookId];

  bool hasFile(String bookId) => _links.containsKey(bookId);

  /// The usual settings, for books without their own look.
  ReaderPrefs get prefs => _prefs;

  /// The settings to read [bookId] with: the usual ones, with the book's
  /// own look when it has one.
  ReaderPrefs prefsFor(String bookId) {
    final own = _links[bookId]?.prefs;
    return own == null ? _prefs : _prefs.withLookOf(own);
  }

  /// Whether [bookId] has its own look.
  bool hasOwnLook(String bookId) => _links[bookId]?.prefs != null;

  Future<void> setLink(String bookId, EbookLink link) async {
    _links[bookId] = link;
    notifyListeners();
    await _save();
  }

  /// Forgets the book's file. Returns the link, so its copy can be deleted.
  Future<EbookLink?> remove(String bookId) async {
    final link = _links.remove(bookId);
    if (link == null) return null;
    notifyListeners();
    await _save();
    return link;
  }

  Future<void> setPosition(String bookId, EbookPosition position) async {
    final link = _links[bookId];
    if (link == null) return;
    _links[bookId] = link.copyWith(position: () => position);
    notifyListeners();
    await _save();
  }

  Future<void> setPageCount(String bookId, int pages) async {
    final link = _links[bookId];
    if (link == null || pages <= 0 || link.pageCount == pages) return;
    _links[bookId] = link.copyWith(pageCount: () => pages);
    notifyListeners();
    await _save();
  }

  /// Adds a bookmark, or does nothing when there is one at that place.
  Future<void> addBookmark(String bookId, EbookBookmark bookmark) async {
    final link = _links[bookId];
    if (link == null) return;
    if (link.bookmarks.any((b) => b.locator == bookmark.locator)) return;
    final bookmarks = [...link.bookmarks, bookmark]
      ..sort((a, b) => a.progress.compareTo(b.progress));
    _links[bookId] = link.copyWith(bookmarks: bookmarks);
    notifyListeners();
    await _save();
  }

  Future<void> removeBookmark(String bookId, String locator) async {
    final link = _links[bookId];
    if (link == null) return;
    _links[bookId] = link.copyWith(
      bookmarks: [
        for (final b in link.bookmarks)
          if (b.locator != locator) b,
      ],
    );
    notifyListeners();
    await _save();
  }

  Future<void> addHighlight(String bookId, EbookHighlight highlight) async {
    final link = _links[bookId];
    if (link == null) return;
    if (link.highlights.any((h) => h.locator == highlight.locator)) return;
    _links[bookId] =
        link.copyWith(highlights: [...link.highlights, highlight]);
    notifyListeners();
    await _save();
  }

  Future<void> removeHighlight(String bookId, String locator) async {
    final link = _links[bookId];
    if (link == null) return;
    _links[bookId] = link.copyWith(
      highlights: [
        for (final h in link.highlights)
          if (h.locator != locator) h,
      ],
    );
    notifyListeners();
    await _save();
  }

  Future<void> setPrefs(ReaderPrefs prefs) async {
    if (prefs == _prefs) return;
    _prefs = prefs;
    notifyListeners();
    await _save();
  }

  /// Saves settings changed while reading [bookId]: the look goes to the
  /// book when it has its own, and the device settings always go to the
  /// usual settings.
  Future<void> applyPrefs(String bookId, ReaderPrefs prefs) async {
    final link = _links[bookId];
    if (link == null || link.prefs == null) {
      await setPrefs(prefs);
      return;
    }
    if (prefs == prefsFor(bookId)) return;
    _links[bookId] = link.copyWith(prefs: () => prefs);
    _prefs = prefs.withLookOf(_prefs);
    notifyListeners();
    await _save();
  }

  /// Gives [bookId] its own look (starting from the one it has now), or
  /// goes back to the usual one.
  Future<void> setOwnLook(String bookId, {required bool own}) async {
    final link = _links[bookId];
    if (link == null || own == (link.prefs != null)) return;
    _links[bookId] = link.copyWith(prefs: () => own ? prefsFor(bookId) : null);
    notifyListeners();
    await _save();
  }

  /// Changes a highlight's colour or note. An empty note removes it.
  Future<void> updateHighlight(
    String bookId,
    String locator, {
    HighlightColour? colour,
    String? Function()? note,
  }) async {
    final link = _links[bookId];
    if (link == null) return;
    String? cleaned() {
      final text = note?.call()?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    _links[bookId] = link.copyWith(
      highlights: [
        for (final h in link.highlights)
          if (h.locator == locator)
            h.copyWith(colour: colour, note: note == null ? null : cleaned)
          else
            h,
      ],
    );
    notifyListeners();
    await _save();
  }

  /// Adds [minutes] in the reader on [date] and the share of the book read
  /// in that time to the book's days.
  Future<void> addReaderTime(
    String bookId,
    DateTime date, {
    required int minutes,
    required double progress,
  }) async {
    final link = _links[bookId];
    if (link == null || minutes <= 0) return;
    final day = DateTime(date.year, date.month, date.day);
    final read = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final days = [...link.days];
    final at = days.indexWhere((d) => d.day == day);
    if (at >= 0) {
      days[at] = EbookDay(
        day: day,
        minutes: days[at].minutes + minutes,
        progress: (days[at].progress + read).clamp(0.0, 1.0),
      );
    } else {
      days
        ..add(EbookDay(day: day, minutes: minutes, progress: read))
        ..sort((a, b) => a.day.compareTo(b.day));
    }
    _links[bookId] = link.copyWith(days: days);
    notifyListeners();
    await _save();
  }

  /// Every book with a file on this device, by book id.
  Map<String, EbookLink> get links => Map.unmodifiable(_links);

  Future<void> _save() async {
    final target = file;
    if (target == null) return;
    try {
      final data = {
        'links': {
          for (final entry in _links.entries) entry.key: entry.value.toJson(),
        },
        'prefs': _prefs.toJson(),
      };
      await target.parent.create(recursive: true);
      // Written beside the real file first, so a crash mid-write never
      // leaves a half-written file.
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(data));
      await temp.rename(target.path);
    } catch (_) {
      // Not saved this time; the next change tries again.
    }
  }
}

/// The page to record as the book's current page: the PDF's own page, or
/// for an EPUB the same share of the book's printed pages. Null when the
/// book has no page count to go by.
int? currentPageFor({
  required EbookFormat format,
  required double progress,
  required int? bookPages,
  int? pdfPage,
}) {
  if (format == EbookFormat.pdf && pdfPage != null && pdfPage > 0) {
    return pdfPage;
  }
  final pages = bookPages;
  if (pages == null || pages <= 0) return null;
  final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
  final page = (p * pages).round();
  return page < 1 ? 1 : (page > pages ? pages : page);
}
