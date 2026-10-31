import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/book_repository.dart';
import '../ebook/ebook_library.dart';
import '../ebook/epub_book.dart';
import '../ebook/reader_style.dart';
import '../models/book.dart';

/// Opens the reader for a book that has a book file on this device.
void openReader(
  BuildContext context, {
  required BookRepository repository,
  required EbookLibrary library,
  required String bookId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        repository: repository,
        library: library,
        bookId: bookId,
      ),
    ),
  );
}

/// The widest the text gets, by margin setting: a comfortable line length
/// however wide the window is.
double _columnWidth(ReaderSpacing margins) => switch (margins) {
      ReaderSpacing.small => 980,
      ReaderSpacing.normal => 760,
      ReaderSpacing.large => 600,
    };

String _fontFamily(ReaderFont font) => switch (font) {
      ReaderFont.serif => 'Georgia',
      ReaderFont.sans => 'Segoe UI',
    };

String _hex(Color colour) {
  String part(double value) =>
      (value * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${part(colour.r)}${part(colour.g)}${part(colour.b)}';
}

final _htmlSpecial = RegExp(r'[&<>"]');

/// Marks the passages you highlighted in a chapter's page. Only passages
/// that appear in the page as they read (not split by formatting) can be
/// marked; the rest are still in the list of highlights.
String markHighlights(String html, Iterable<String> passages) {
  var result = html;
  for (final passage in passages) {
    final text = passage.trim();
    if (text.length < 3) continue;
    final escaped = text.replaceAllMapped(
      _htmlSpecial,
      (m) => switch (m[0]) {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        _ => '&quot;',
      },
    );
    for (final candidate in {text, escaped}) {
      final at = result.indexOf(candidate);
      if (at >= 0) {
        result = '${result.substring(0, at)}<mark>$candidate</mark>'
            '${result.substring(at + candidate.length)}';
        break;
      }
    }
  }
  return result;
}

/// Reads a book's EPUB or PDF file in the window. An EPUB scrolls one
/// chapter at a time. Where you are is saved, the book's current page is
/// kept up to date, and the time you spend reading goes into the reading
/// log.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.repository,
    required this.library,
    required this.bookId,
    this.now = DateTime.now,
  });

  final BookRepository repository;
  final EbookLibrary library;
  final String bookId;
  final DateTime Function() now;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum _Panel { contents, appearance }

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  final _pdf = PdfViewerController();
  final _focus = FocusNode();

  _Panel _panel = _Panel.contents;
  String? _problem;
  bool _loading = true;

  // EPUB
  EpubBook? _book;
  List<int> _lengths = const [];
  int _chapter = 0;
  double _fraction = 0;

  /// Where to scroll to once the chapter is laid out.
  double? _restore;
  String? _selected;

  // PDF
  int? _pdfPage;
  int? _pdfPages;

  Timer? _saveTimer;
  EbookPosition? _unsaved;

  /// Reading time not yet in the reading log.
  final _reading = Stopwatch();
  Duration _carried = Duration.zero;
  Timer? _logTimer;

  EbookLink? get _link => widget.library.linkFor(widget.bookId);
  Book? get _entry => widget.repository.byId(widget.bookId);
  ReaderPrefs get _prefs => widget.library.prefs;
  bool get _isPdf => _link?.format == EbookFormat.pdf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scrolled);
    _open();
    _reading.start();
    _logTimer = Timer.periodic(const Duration(minutes: 5), (_) => _logTime());
  }

  Future<void> _open() async {
    final link = _link;
    final exists = link != null && await File(link.path).exists();
    if (!mounted) return;
    if (link == null || !exists) {
      setState(() {
        _loading = false;
        _problem = 'The book file is missing on this PC. Add it again from '
            'the book page.';
      });
      return;
    }
    if (link.format == EbookFormat.pdf) {
      setState(() => _loading = false);
      return;
    }
    try {
      final book = EpubBook.open(await File(link.path).readAsBytes());
      final lengths = [
        for (var i = 0; i < book.chapters.length; i++)
          book.chapterText(i).length,
      ];
      final spot = EpubSpot.parse(link.position?.locator);
      if (!mounted) return;
      setState(() {
        _book = book;
        _lengths = lengths;
        _chapter = spot == null ? 0 : spot.chapter.clamp(0, lengths.length - 1);
        _fraction = spot?.fraction ?? 0;
        _restore = _fraction;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = 'This book file could not be opened. It may be damaged '
            'or locked (DRM).';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reading.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _reading.stop();
      _flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _logTimer?.cancel();
    _reading.stop();
    _scroll.dispose();
    _focus.dispose();
    final position = _unsaved;
    _unsaved = null;
    final minutes = _takeMinutes();
    final repository = widget.repository;
    final library = widget.library;
    final bookId = widget.bookId;
    final now = widget.now();
    // Saved just after the screen is gone: saving tells the book page to
    // redraw, which Flutter does not allow while it is removing a screen.
    scheduleMicrotask(() => _writeOut(
          repository: repository,
          library: library,
          bookId: bookId,
          position: position,
          minutes: minutes,
          now: now,
        ));
    super.dispose();
  }

  void _flush() {
    _saveTimer?.cancel();
    final position = _unsaved;
    _unsaved = null;
    _writeOut(
      repository: widget.repository,
      library: widget.library,
      bookId: widget.bookId,
      position: position,
      minutes: _takeMinutes(),
      now: widget.now(),
    );
  }

  /// Takes the whole minutes of reading so far; the seconds left over wait
  /// for the next time.
  int _takeMinutes() {
    final total = _carried + _reading.elapsed;
    _reading.reset();
    final minutes = total.inMinutes;
    _carried = total - Duration(minutes: minutes);
    return minutes;
  }

  void _logTime() {
    final minutes = _takeMinutes();
    if (minutes > 0) {
      widget.repository.addReadingMinutes(widget.bookId, widget.now(), minutes);
    }
  }

  /// Saves the position, keeps the book's current page up to date and adds
  /// the reading time to the reading log.
  static void _writeOut({
    required BookRepository repository,
    required EbookLibrary library,
    required String bookId,
    required EbookPosition? position,
    required int minutes,
    required DateTime now,
  }) {
    if (position != null) {
      library.setPosition(bookId, position);
      final book = repository.byId(bookId);
      final link = library.linkFor(bookId);
      if (book != null && link != null) {
        final page = currentPageFor(
          format: link.format,
          progress: position.progress,
          bookPages: book.pages,
          pdfPage: link.format == EbookFormat.pdf
              ? int.tryParse(position.locator)
              : null,
        );
        if (page != null && page != book.currentPage) {
          repository.setCurrentPage(bookId, page);
        }
      }
    }
    if (minutes > 0) repository.addReadingMinutes(bookId, now, minutes);
  }

  /// Remembers where you are, saving it a moment later.
  void _moved(EbookPosition position) {
    _unsaved = position;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final p = _unsaved;
      if (p == null) return;
      _unsaved = null;
      widget.library.setPosition(widget.bookId, p);
    });
  }

  double get _progress {
    if (_isPdf) {
      final page = _pdfPage;
      final pages = _pdfPages;
      if (page == null || pages == null || pages <= 1) return 0;
      return (page - 1) / (pages - 1);
    }
    if (_book == null) return _link?.position?.progress ?? 0;
    return bookProgress(_lengths, EpubSpot(_chapter, _fraction));
  }

  String? get _locator {
    if (_isPdf) {
      final page = _pdfPage;
      return page == null ? null : '$page';
    }
    if (_book == null) return null;
    return EpubSpot(_chapter, _fraction).locator;
  }

  // ---- EPUB ----

  void _scrolled() {
    if (!_scroll.hasClients || _book == null) return;
    final max = _scroll.position.maxScrollExtent;
    final fraction = max <= 0 ? 0.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    final before = (_progress * 100).round();
    _fraction = fraction;
    if ((_progress * 100).round() != before) setState(() {});
    _savePosition();
  }

  void _savePosition() {
    final book = _book;
    if (book == null) return;
    _moved(EbookPosition(
      locator: EpubSpot(_chapter, _fraction).locator,
      progress: _progress,
      chapter: book.chapterTitle(_chapter),
    ));
  }

  void _goToChapter(int chapter, {double fraction = 0}) {
    final book = _book;
    if (book == null) return;
    final target = chapter.clamp(0, book.chapters.length - 1);
    setState(() {
      _chapter = target;
      _fraction = fraction;
      _restore = fraction;
    });
    _savePosition();
  }

  /// Scrolls to where you were once the chapter is laid out.
  void _restoreScroll() {
    final restore = _restore;
    if (restore == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _restore = null;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((restore * max).clamp(0.0, max));
    });
  }

  /// Down (or up) one screen; past the end of a chapter, the next one.
  void _page(int direction) {
    if (_isPdf) {
      final page = (_pdfPage ?? 1) + direction;
      final pages = _pdfPages ?? 1;
      if (page >= 1 && page <= pages) _pdf.goToPage(pageNumber: page);
      return;
    }
    final book = _book;
    if (book == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    final step = position.viewportDimension * 0.9;
    if (direction > 0) {
      if (position.pixels >= position.maxScrollExtent - 1) {
        if (_chapter < book.chapters.length - 1) _goToChapter(_chapter + 1);
        return;
      }
      _scroll.animateTo(
        (position.pixels + step).clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      if (position.pixels <= 1) {
        if (_chapter > 0) _goToChapter(_chapter - 1, fraction: 1);
        return;
      }
      _scroll.animateTo(
        (position.pixels - step).clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  Future<bool> _tapLink(String url) async {
    final book = _book;
    if (book == null) return false;
    final target = book.linkTarget(_chapter, url);
    if (target != null) {
      _goToChapter(target);
      return true;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  Future<void> _saveQuote() async {
    final text = _selected?.trim() ?? '';
    final entry = _entry;
    if (text.isEmpty || entry == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.library.addHighlight(
      widget.bookId,
      EbookHighlight(
        // The time keeps two highlights at the same place apart.
        locator: '${_locator ?? 'c:$_chapter:0'}:'
            '${widget.now().millisecondsSinceEpoch}',
        text: text,
        addedAt: widget.now(),
      ),
    );
    final link = _link;
    final page = link == null
        ? null
        : currentPageFor(
            format: link.format,
            progress: _progress,
            bookPages: entry.pages,
            pdfPage: _pdfPage,
          );
    await widget.repository.addQuote(widget.bookId, text, page: page);
    messenger.showSnackBar(
      const SnackBar(content: Text('Highlighted and saved to your quotes')),
    );
  }

  // ---- PDF ----

  void _pdfPageChanged(int? page) {
    if (page == null) return;
    setState(() => _pdfPage = page);
    _moved(EbookPosition(locator: '$page', progress: _progress));
  }

  void _pdfReady(PdfDocument document, PdfViewerController controller) {
    final pages = document.pages.length;
    setState(() => _pdfPages = pages);
    widget.library.setPageCount(widget.bookId, pages);
    final entry = _entry;
    if (entry != null && entry.pages == null && pages > 0) {
      widget.repository.setPages(widget.bookId, pages);
    }
  }

  // ---- Tools ----

  void _toggleBookmark() {
    final link = _link;
    final locator = _locator;
    if (link == null || locator == null) return;
    if (link.bookmarks.any((b) => b.locator == locator)) {
      widget.library.removeBookmark(widget.bookId, locator);
      return;
    }
    final label = _isPdf
        ? 'Page $locator'
        : '${_book?.chapterTitle(_chapter) ?? 'Part ${_chapter + 1}'}, '
            '${percentText(_fraction)} in';
    widget.library.addBookmark(
      widget.bookId,
      EbookBookmark(
        locator: locator,
        progress: _progress,
        label: label,
        addedAt: widget.now(),
      ),
    );
  }

  void _goTo(String locator) {
    if (_isPdf) {
      final page = int.tryParse(locator);
      if (page != null) _pdf.goToPage(pageNumber: page);
      return;
    }
    final spot = EpubSpot.parse(locator);
    if (spot != null) _goToChapter(spot.chapter, fraction: spot.fraction);
  }

  void _goToProgress(double value) {
    if (_isPdf) {
      final pages = _pdfPages;
      if (pages == null || pages <= 0) return;
      _pdf.goToPage(pageNumber: 1 + (value * (pages - 1)).round());
      return;
    }
    if (_book == null) return;
    final spot = spotForProgress(_lengths, value);
    _goToChapter(spot.chapter, fraction: spot.fraction);
  }

  void _openPanel(_Panel panel) {
    setState(() => _panel = panel);
    _scaffold.currentState?.openEndDrawer();
  }

  Future<void> _setPrefs(ReaderPrefs prefs) async {
    // Keep the same place in the chapter when the text changes size.
    if (!_isPdf) _restore = _fraction;
    await widget.library.setPrefs(prefs);
  }

  Future<void> _search() async {
    final book = _book;
    if (book == null) return;
    final chosen = await showDialog<EpubSearchHit>(
      context: context,
      builder: (dialogContext) => _SearchDialog(book: book),
    );
    if (chosen != null) {
      _goToChapter(chosen.chapter, fraction: chosen.fraction);
    }
  }

  // ---- Building ----

  Widget _epubView(EpubBook book, ReaderColors colours) {
    _restoreScroll();
    final prefs = _prefs;
    final link = _link;
    final html = markHighlights(
      book.chapterHtml(_chapter),
      [
        for (final h in link?.highlights ?? const <EbookHighlight>[])
          if (EpubSpot.parse(h.locator)?.chapter == _chapter) h.text,
      ],
    );
    final textStyle = TextStyle(
      fontSize: prefs.fontSize.toDouble(),
      height: readerLineHeight(prefs.lineSpacing),
      fontFamily: _fontFamily(prefs.font),
      color: colours.foreground,
    );
    final last = _chapter >= book.chapters.length - 1;
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _columnWidth(prefs.margins)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectionArea(
                  onSelectionChanged: (content) =>
                      _selected = content?.plainText,
                  contextMenuBuilder: (context, state) =>
                      AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: [
                      ...state.contextMenuButtonItems,
                      ContextMenuButtonItem(
                        label: 'Highlight and save quote',
                        onPressed: () {
                          state.hideToolbar();
                          _saveQuote();
                        },
                      ),
                    ],
                  ),
                  child: HtmlWidget(
                    html,
                    key: ValueKey('$_chapter-${prefs.hashCode}-${html.length}'),
                    textStyle: textStyle,
                    buildAsync: false,
                    onTapUrl: _tapLink,
                    customStylesBuilder: (element) {
                      if (element.localName == 'mark') {
                        return {
                          'background-color': _hex(colours.highlight),
                          'color': _hex(colours.foreground),
                        };
                      }
                      if (element.localName == 'a') {
                        return {'color': _hex(colours.foreground)};
                      }
                      return null;
                    },
                    customWidgetBuilder: (element) {
                      if (element.localName != 'img') return null;
                      final src = element.attributes['src'];
                      final bytes =
                          src == null ? null : book.resource(_chapter, src);
                      if (bytes == null || bytes.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 640),
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stack) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    if (_chapter > 0)
                      TextButton.icon(
                        onPressed: () => _goToChapter(_chapter - 1),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous chapter'),
                      ),
                    const Spacer(),
                    if (!last)
                      FilledButton.icon(
                        onPressed: () => _goToChapter(_chapter + 1),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next chapter'),
                      )
                    else
                      Text(
                        'The end',
                        style: TextStyle(color: colours.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pdfView(EbookLink link, ReaderColors colours) {
    final saved = int.tryParse(link.position?.locator ?? '');
    return PdfViewer.file(
      link.path,
      controller: _pdf,
      initialPageNumber: saved != null && saved > 0 ? saved : 1,
      params: PdfViewerParams(
        backgroundColor: colours.background,
        onPageChanged: _pdfPageChanged,
        onViewerReady: _pdfReady,
      ),
    );
  }

  Widget _bottomBar(ReaderColors colours) {
    final book = _book;
    final entry = _entry;
    final link = _link;
    final page = link == null || entry == null
        ? null
        : currentPageFor(
            format: link.format,
            progress: _progress,
            bookPages: entry.pages,
            pdfPage: _pdfPage,
          );
    final where = <String>[
      if (book != null)
        book.chapterTitle(_chapter) ??
            'Part ${_chapter + 1} of ${book.chapters.length}',
      if (_isPdf && _pdfPage != null)
        'Page $_pdfPage of ${_pdfPages ?? '?'}'
      else if (page != null && entry?.pages != null)
        'About page $page of ${entry!.pages}',
    ];
    final textStyle = TextStyle(color: colours.muted, fontSize: 12);
    return Material(
      color: colours.bar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                where.join(' · '),
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: _ProgressSlider(value: _progress, onDone: _goToProgress),
            ),
            SizedBox(
              width: 44,
              child: Text(
                percentText(_progress),
                style: textStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelView() {
    return switch (_panel) {
      _Panel.contents => _ContentsPanel(
          library: widget.library,
          bookId: widget.bookId,
          book: _book,
          chapter: _chapter,
          onGo: (locator) {
            Navigator.of(context).maybePop();
            _goTo(locator);
          },
          onChapter: (chapter) {
            Navigator.of(context).maybePop();
            _goToChapter(chapter);
          },
        ),
      _Panel.appearance => _AppearancePanel(
          library: widget.library,
          pdf: _isPdf,
          onChanged: _setPrefs,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final colours = readerColors(_prefs.theme);
        final link = _link;
        final entry = _entry;
        final problem = _problem;
        if (link == null || entry == null || problem != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reader')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  problem ?? 'This book has no book file on this PC.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final locator = _locator;
        final marked =
            locator != null && link.bookmarks.any((b) => b.locator == locator);
        final book = _book;
        final Widget body;
        if (_loading) {
          body = const Center(child: CircularProgressIndicator());
        } else if (_isPdf) {
          body = _pdfView(link, colours);
        } else if (book != null) {
          body = _epubView(book, colours);
        } else {
          body = const SizedBox.shrink();
        }
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.pageDown): () => _page(1),
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _page(-1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _page(1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _page(-1),
            const SingleActivator(LogicalKeyboardKey.space): () => _page(1),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _search,
            const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                _toggleBookmark,
            const SingleActivator(LogicalKeyboardKey.equal, control: true):
                () => _setPrefs(_prefs.copyWith(fontSize: _prefs.fontSize + 1)),
            const SingleActivator(LogicalKeyboardKey.minus, control: true):
                () => _setPrefs(_prefs.copyWith(fontSize: _prefs.fontSize - 1)),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            child: Scaffold(
              key: _scaffold,
              backgroundColor: colours.background,
              endDrawer: Drawer(width: 380, child: _panelView()),
              appBar: AppBar(
                backgroundColor: colours.bar,
                foregroundColor: colours.foreground,
                titleSpacing: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (entry.author.isNotEmpty)
                      Text(
                        entry.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colours.muted, fontSize: 12),
                      ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: _isPdf ? 'Bookmarks' : 'Contents and bookmarks',
                    icon: const Icon(Icons.format_list_bulleted),
                    onPressed: () => _openPanel(_Panel.contents),
                  ),
                  if (!_isPdf)
                    IconButton(
                      tooltip: 'Search in the book (Ctrl+F)',
                      icon: const Icon(Icons.search),
                      onPressed: book == null ? null : _search,
                    ),
                  IconButton(
                    tooltip: marked
                        ? 'Remove the bookmark (Ctrl+B)'
                        : 'Bookmark this place (Ctrl+B)',
                    icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
                    color: marked ? Theme.of(context).colorScheme.primary : null,
                    onPressed: locator == null ? null : _toggleBookmark,
                  ),
                  IconButton(
                    tooltip: _isPdf ? 'Theme' : 'Text and theme',
                    icon: const Icon(Icons.text_fields),
                    onPressed: () => _openPanel(_Panel.appearance),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Column(
                children: [
                  Expanded(child: body),
                  _bottomBar(colours),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The position slider: moves while you drag, and goes there when you let
/// go.
class _ProgressSlider extends StatefulWidget {
  const _ProgressSlider({required this.value, required this.onDone});

  final double value;
  final ValueChanged<double> onDone;

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(0.0, 1.0);
    return Slider(
      value: value,
      label: percentText(value),
      divisions: 200,
      onChanged: (v) => setState(() => _dragging = v),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        widget.onDone(v);
      },
    );
  }
}

/// Searches the book and lists where the words are.
class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.book});

  final EpubBook book;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();
  List<EpubSearchHit>? _hits;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run() {
    setState(() => _hits = widget.book.search(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return AlertDialog(
      title: const Text('Search in the book'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Words to find',
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: _run,
                ),
              ),
              onSubmitted: (_) => _run(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: hits == null
                  ? const SizedBox.shrink()
                  : hits.isEmpty
                      ? const Center(child: Text('Not found in this book.'))
                      : ListView.builder(
                          itemCount: hits.length,
                          itemBuilder: (context, i) {
                            final hit = hits[i];
                            return ListTile(
                              title: Text(
                                hit.excerpt,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                widget.book.chapterTitle(hit.chapter) ??
                                    'Part ${hit.chapter + 1}',
                              ),
                              onTap: () => Navigator.of(context).pop(hit),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Text size, theme, typeface, spacing and width. A PDF only takes the
/// theme (the colour around the pages).
class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.library,
    required this.pdf,
    required this.onChanged,
  });

  final EbookLibrary library;
  final bool pdf;
  final Future<void> Function(ReaderPrefs prefs) onChanged;

  Widget _segments<T>({
    required List<(T, String)> choices,
    required T selected,
    required ValueChanged<T> onSelected,
  }) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final (value, label) in choices)
          ButtonSegment<T>(value: value, label: Text(label)),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onSelected(values.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final prefs = library.prefs;
        Widget label(String text) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(text, style: textTheme.labelLarge),
            );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(pdf ? 'Theme' : 'Text and theme', style: textTheme.titleLarge),
            if (!pdf) ...[
              label('Text size (Ctrl+= and Ctrl+-)'),
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Slider(
                      value: prefs.fontSize.toDouble(),
                      min: ReaderPrefs.minFontSize.toDouble(),
                      max: ReaderPrefs.maxFontSize.toDouble(),
                      divisions:
                          ReaderPrefs.maxFontSize - ReaderPrefs.minFontSize,
                      label: '${prefs.fontSize}',
                      onChanged: (v) =>
                          onChanged(prefs.copyWith(fontSize: v.round())),
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 26)),
                ],
              ),
            ],
            label('Theme'),
            Row(
              children: [
                for (final theme in ReaderTheme.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message: '${readerThemeLabel(theme)} theme',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onChanged(prefs.copyWith(theme: theme)),
                          child: Column(
                            children: [
                              Container(
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: readerColors(theme).background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: prefs.theme == theme
                                        ? accent
                                        : readerColors(theme).muted,
                                    width: prefs.theme == theme ? 3 : 1,
                                  ),
                                ),
                                child: Text(
                                  'Aa',
                                  style: TextStyle(
                                    color: readerColors(theme).foreground,
                                    fontFamily: 'Georgia',
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                readerThemeLabel(theme),
                                style: textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (!pdf) ...[
              label('Typeface'),
              _segments<ReaderFont>(
                choices: const [
                  (ReaderFont.serif, 'Serif'),
                  (ReaderFont.sans, 'Sans'),
                ],
                selected: prefs.font,
                onSelected: (font) => onChanged(prefs.copyWith(font: font)),
              ),
              label('Line spacing'),
              _segments<ReaderSpacing>(
                choices: [
                  for (final s in ReaderSpacing.values)
                    (s, readerSpacingLabel(s)),
                ],
                selected: prefs.lineSpacing,
                onSelected: (s) => onChanged(prefs.copyWith(lineSpacing: s)),
              ),
              label('Margins'),
              _segments<ReaderSpacing>(
                choices: [
                  for (final s in ReaderSpacing.values)
                    (s, readerSpacingLabel(s)),
                ],
                selected: prefs.margins,
                onSelected: (s) => onChanged(prefs.copyWith(margins: s)),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Chapters (EPUB), bookmarks and highlights.
class _ContentsPanel extends StatelessWidget {
  const _ContentsPanel({
    required this.library,
    required this.bookId,
    required this.book,
    required this.chapter,
    required this.onGo,
    required this.onChapter,
  });

  final EbookLibrary library;
  final String bookId;
  final EpubBook? book;
  final int chapter;
  final ValueChanged<String> onGo;
  final ValueChanged<int> onChapter;

  @override
  Widget build(BuildContext context) {
    final epub = book;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final link = library.linkFor(bookId);
        final bookmarks = link?.bookmarks ?? const <EbookBookmark>[];
        final highlights = link?.highlights ?? const <EbookHighlight>[];
        final tabs = <(String, Widget)>[
          if (epub != null)
            (
              'Chapters',
              epub.toc.isEmpty
                  ? ListView(
                      children: [
                        for (var i = 0; i < epub.chapters.length; i++)
                          ListTile(
                            selected: i == chapter,
                            title: Text('Part ${i + 1}'),
                            onTap: () => onChapter(i),
                          ),
                      ],
                    )
                  : ListView(
                      children: [
                        for (final entry in epub.toc)
                          ListTile(
                            selected: entry.chapter == chapter,
                            selectedTileColor:
                                scheme.secondaryContainer.withValues(alpha: 0.5),
                            contentPadding: EdgeInsets.only(
                              left: 16.0 + entry.depth * 20,
                              right: 16,
                            ),
                            title: Text(entry.title),
                            onTap: () => onChapter(entry.chapter),
                          ),
                      ],
                    ),
            ),
          (
            'Bookmarks (${bookmarks.length})',
            bookmarks.isEmpty
                ? const _Empty(
                    'No bookmarks yet. Use the bookmark at the top, or Ctrl+B.',
                  )
                : ListView(
                    children: [
                      for (final bookmark in bookmarks)
                        ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(bookmark.label),
                          subtitle: Text(percentText(bookmark.progress)),
                          trailing: IconButton(
                            tooltip: 'Remove the bookmark',
                            icon: const Icon(Icons.clear),
                            onPressed: () =>
                                library.removeBookmark(bookId, bookmark.locator),
                          ),
                          onTap: () => onGo(bookmark.locator),
                        ),
                    ],
                  ),
          ),
          if (epub != null)
            (
              'Highlights (${highlights.length})',
              highlights.isEmpty
                  ? const _Empty(
                      'No highlights yet. Select a passage, right-click it and '
                      'choose "Highlight and save quote".',
                    )
                  : ListView(
                      children: [
                        for (final highlight in highlights)
                          ListTile(
                            leading: const Icon(Icons.format_quote),
                            title: Text(
                              highlight.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove the highlight (the quote '
                                  'stays on the book page)',
                              icon: const Icon(Icons.clear),
                              onPressed: () => library.removeHighlight(
                                bookId,
                                highlight.locator,
                              ),
                            ),
                            onTap: () => onGo(highlight.locator),
                          ),
                      ],
                    ),
            ),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: tabs.length > 2,
                tabs: [for (final (label, _) in tabs) Tab(text: label)],
              ),
              Expanded(
                child: TabBarView(
                  children: [for (final (_, view) in tabs) view],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
