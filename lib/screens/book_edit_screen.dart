import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_repository.dart';
import '../data/book_source.dart';
import '../data/cover_image.dart';
import '../data/file_match.dart';
import '../data/open_library_client.dart';
import '../models/book.dart';
import '../widgets/book_cover.dart';

// The same file is in the Android app; keep the two copies alike.

/// Opens the book editor: correct the title, author and other details, pick
/// the right book from Open Library when the match was wrong, or change the
/// cover. A page of its own on a phone, a dialog on a wide window.
Future<void> openBookEditor(
  BuildContext context, {
  required BookRepository repository,
  required String bookId,
  OpenLibraryClient? client,
}) async {
  final openLibrary = client ?? OpenLibraryClient();
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final String? problem;
  if (wide) {
    problem = await showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 760),
          child: BookEditor(
            repository: repository,
            bookId: bookId,
            client: openLibrary,
            wide: true,
          ),
        ),
      ),
    );
  } else {
    problem = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BookEditor(
          repository: repository,
          bookId: bookId,
          client: openLibrary,
          wide: false,
        ),
      ),
    );
  }
  if (problem != null && problem.isNotEmpty && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(problem)));
  }
}

/// The editor. Pops with a problem to show (from the book server), an empty
/// text when saved, or null when cancelled.
class BookEditor extends StatefulWidget {
  const BookEditor({
    super.key,
    required this.repository,
    required this.bookId,
    required this.client,
    required this.wide,
  });

  final BookRepository repository;
  final String bookId;
  final OpenLibraryClient client;
  final bool wide;

  @override
  State<BookEditor> createState() => _BookEditorState();
}

class _BookEditorState extends State<BookEditor> {
  late final Book _book = widget.repository.byId(widget.bookId)!;
  late final _title = TextEditingController(text: _book.title);
  late final _author = TextEditingController(text: _book.author);
  late final _series = TextEditingController(text: _book.series ?? '');
  late final _seriesNumber =
      TextEditingController(text: _book.seriesNumber?.toString() ?? '');
  late final _isbn = TextEditingController(text: _book.isbn ?? '');
  late final _pages = TextEditingController(text: _book.pages?.toString() ?? '');
  late final _year =
      TextEditingController(text: _book.firstPublishYear?.toString() ?? '');

  /// A cover picked here, not saved yet.
  CoverChange? _cover;
  late bool _onServer = serverIdFor(_book.id) != null;
  late final bool _serverLinked = _onServer;
  late final Future<String?> _fromServer = serverFileName(_book.id);
  bool _saving = false;
  String? _titleProblem;

  @override
  void dispose() {
    for (final controller in [
      _title, _author, _series, _seriesNumber, _isbn, _pages, _year,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _number(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  String? get _shownCover => _cover != null ? _cover!.value : _book.coverUrl;

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleProblem = 'A book needs a title.');
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await widget.repository.editDetails(
      _book.id,
      BookDetails(
        title: _title.text,
        author: _author.text,
        series: _series.text,
        seriesNumber: _number(_seriesNumber),
        isbn: _isbn.text,
        pages: _number(_pages),
        year: _number(_year),
        coverUrl: _cover,
      ),
    );
    String? problem;
    final saved = widget.repository.byId(_book.id);
    if (_serverLinked && _onServer && saved != null) {
      problem = await correctOnServer(saved);
    }
    navigator.pop(problem ?? '');
  }

  Future<void> _reset() async {
    final origin = _book.origin;
    if (origin == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to the matched info?'),
        content: Text(
          'The title, author, series, ISBN, pages and year go back to how '
          'the book was added: "${origin.title}"'
          '${origin.author.isEmpty ? '' : ' by ${origin.author}'}. '
          'The cover stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final navigator = Navigator.of(context);
    await widget.repository.resetDetails(_book.id);
    String? problem;
    final saved = widget.repository.byId(_book.id);
    if (_serverLinked && _onServer && saved != null) {
      problem = await correctOnServer(saved);
    }
    navigator.pop(problem ?? '');
  }

  Future<void> _findMatch(String? originalName) async {
    final query = originalName != null
        ? cleanFileName(originalName)
        : '${_title.text} ${_author.text}'.trim();
    final picked = await showDialog<OpenLibraryBook>(
      context: context,
      builder: (_) => MatchPicker(client: widget.client, initialQuery: query),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _title.text = picked.title;
      _author.text = picked.author;
      if (picked.isbn case final isbn?) _isbn.text = isbn;
      if (picked.pages case final pages?) _pages.text = '$pages';
      if (picked.firstPublishYear case final year?) _year.text = '$year';
      if (picked.coverUrl case final cover?) _cover = CoverChange(cover);
      _titleProblem = null;
    });
  }

  Future<void> _choosePicture() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Pictures',
          extensions: coverExtensions,
          mimeTypes: ['image/*'],
        ),
      ],
    );
    if (file == null) return;
    final cover = await makeDataCover(await file.readAsBytes());
    if (!mounted) return;
    if (cover == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('That file is not a picture Chapterly can read.'),
        ),
      );
      return;
    }
    setState(() => _cover = CoverChange(cover));
  }

  @override
  Widget build(BuildContext context) {
    final saveButton = FilledButton(
      onPressed: _saving ? null : _save,
      child: const Text('Save'),
    );
    final body = FutureBuilder<String?>(
      future: _fromServer,
      builder: (context, snapshot) {
        final original = _book.origin?.name ??
            snapshot.data ??
            linkedFileName(_book.id);
        return _form(context, original);
      },
    );
    if (widget.wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit book',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Flexible(child: SingleChildScrollView(child: body)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_book.origin != null)
                  OutlinedButton(
                    onPressed: _saving ? null : _reset,
                    child: const Text('Reset to the matched info'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                saveButton,
              ],
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Edit book'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: saveButton,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body,
              if (_book.origin != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _reset,
                    child: const Text('Reset to the matched info'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, String? original) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final match = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WRONG MATCH?',
                  style: text.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  original == null
                      ? 'Search Open Library and pick the right book.'
                      : 'Original name: $original',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : () => _findMatch(original),
            child: const Text('Find match'),
          ),
        ],
      ),
    );
    final cover = Column(
      crossAxisAlignment: widget.wide
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        BookCover(
          coverUrl: _shownCover,
          title: _title.text,
          width: widget.wide ? 160 : 84,
          height: widget.wide ? 240 : 126,
          shadow: true,
        ),
      ],
    );
    final coverButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      direction: widget.wide ? Axis.vertical : Axis.horizontal,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined),
          label: const Text('Choose picture'),
          onPressed: _saving ? null : _choosePicture,
        ),
        if (_shownCover != null)
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() => _cover = const CoverChange(null)),
            child: const Text('Remove cover'),
          ),
      ],
    );
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Title',
            errorText: _titleProblem,
          ),
          onChanged: (_) => setState(() => _titleProblem = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _author,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Author'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _series,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Series'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _seriesNumber,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Number'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _isbn,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ISBN'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pages,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Pages'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration:
                    const InputDecoration(labelText: 'First published'),
              ),
            ),
          ],
        ),
        if (_serverLinked)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _onServer,
            onChanged: (value) => setState(() => _onServer = value ?? false),
            title: const Text('Also correct it on the book server'),
            subtitle: const Text(
              'The title, author and series, for everyone using the server. '
              'The book file is not changed.',
            ),
          ),
        if (_book.origin?.edited ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'You have corrected this book before. Your corrections stay '
              'when Open Library details are filled in.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
    if (widget.wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          match,
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: Column(
                  children: [cover, const SizedBox(height: 12), coverButtons],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: fields),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        match,
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            cover,
            const SizedBox(width: 16),
            Expanded(child: coverButtons),
          ],
        ),
        const SizedBox(height: 18),
        fields,
      ],
    );
  }
}

/// Searches Open Library and lets you pick the right book. Pops with it.
class MatchPicker extends StatefulWidget {
  const MatchPicker({
    super.key,
    required this.client,
    required this.initialQuery,
  });

  final OpenLibraryClient client;
  final String initialQuery;

  @override
  State<MatchPicker> createState() => _MatchPickerState();
}

class _MatchPickerState extends State<MatchPicker> {
  late final _query = TextEditingController(text: widget.initialQuery);
  Future<List<OpenLibraryBook>>? _results;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    setState(() => _results = widget.client.search(_query.text));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Text('Find the right book'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: widget.initialQuery.isEmpty,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Title, author or ISBN',
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<List<OpenLibraryBook>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Could not reach Open Library. Check your '
                              'connection and try again.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        final books = snapshot.data ?? const [];
                        if (books.isEmpty) {
                          return const Center(
                            child: Text(
                              'Nothing found. Try fewer words, or the '
                              "author's last name.",
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: books.length,
                          itemBuilder: (context, index) {
                            final book = books[index];
                            final line = [
                              if (book.author.isNotEmpty) book.author,
                              if (book.firstPublishYear case final year?)
                                '$year',
                            ].join(' · ');
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: BookCover(
                                coverUrl: book.coverUrl,
                                title: book.title,
                              ),
                              title: Text(book.title),
                              subtitle: line.isEmpty
                                  ? null
                                  : Text(line, style: TextStyle(color: muted)),
                              onTap: () => Navigator.of(context).pop(book),
                            );
                          },
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
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
