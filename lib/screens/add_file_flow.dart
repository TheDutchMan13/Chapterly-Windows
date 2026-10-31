import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio/audio_files.dart';
import '../audio/audio_library.dart';
import '../audio/audio_tags.dart';
import '../audio/listening.dart';
import '../data/book_repository.dart';
import '../data/file_match.dart';
import '../ebook/ebook_files.dart';
import '../ebook/ebook_library.dart';
import '../ebook/ebook_reading.dart';
import '../ebook/epub_info.dart';
import '../ebook/pdf_info.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'reader_screen.dart';

/// What the Add file button opens.
enum AddFileKind { book, audioFile, audioFolder }

/// Book files bigger than this are matched by their file name only.
const _readLimit = 64 * 1024 * 1024;

/// The work of the Add file button: pick an EPUB, PDF or audiobook, find
/// the book in the library it belongs to (from the title and author in the
/// file, or its name), let you confirm or pick another, link the file and
/// show the book. [onLinked] gets the book's id.
Future<void> addFileToLibrary(
  BuildContext context, {
  required BookRepository repository,
  required AddFileKind kind,
  required void Function(String bookId) onLinked,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void cannotPick() => messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the file picker.')),
      );

  if (kind == AddFileKind.book) {
    final files = EbookReading.files;
    if (files == null) return;
    final PickedFile? picked;
    try {
      picked = await files.pickBook();
    } catch (_) {
      cannotPick();
      return;
    }
    if (picked == null || !context.mounted) return;
    await linkBookFile(
      context,
      repository: repository,
      picked: picked,
      onLinked: onLinked,
    );
    return;
  }

  final files = Listening.files;
  if (files == null || Listening.controller == null) return;
  final folder = kind == AddFileKind.audioFolder;
  final List<PickedFile>? picked;
  try {
    picked = folder ? await files.pickFolder() : await files.pickFile();
  } catch (_) {
    cannotPick();
    return;
  }
  if (picked == null || !context.mounted) return;
  await linkAudiobook(
    context,
    repository: repository,
    picked: picked,
    folder: folder,
    onLinked: onLinked,
  );
}

/// Every audio file in [folder] and its subfolders, named by their place
/// inside it ("CD 1/01.mp3"), as the Add file button picks a folder.
Future<List<PickedFile>> audioFilesIn(String folder) async {
  final files = <PickedFile>[];
  await for (final entity in Directory(folder).list(recursive: true)) {
    if (entity is! File || !isAudioFileName(entity.path)) continue;
    files.add(PickedFile(
      location: entity.path,
      name: p.relative(entity.path, from: folder),
    ));
  }
  return files;
}

/// Links one EPUB or PDF (picked or dropped on the window) to its book:
/// asks which book, copies the file in, and shows the book.
Future<void> linkBookFile(
  BuildContext context, {
  required BookRepository repository,
  required PickedFile picked,
  required void Function(String bookId) onLinked,
}) async {
  final library = EbookReading.library;
  final files = EbookReading.files;
  final booksDir = EbookReading.booksDir;
  if (library == null || files == null || booksDir == null) return;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final format = ebookFormatOf(picked.name);
  if (format == null) {
    say('Chapterly can open EPUB and PDF files. '
        '"${picked.name}" is neither.');
    return;
  }
  final found = await _bookFileInfo(files, booksDir, picked, format);
  if (!context.mounted) return;
  final choice = await _askWhichBook(
    context,
    repository: repository,
    fileName: picked.name,
    found: found,
    nameParts: fileNameParts(picked.name),
    audio: false,
    hasFile: (id) => library.linkFor(id) != null,
  );
  if (choice == null || !context.mounted) {
    await files.release(picked);
    return;
  }
  final bookId = await _bookFor(choice, repository, BookFormat.ebook);
  if (bookId == null) {
    await files.release(picked);
    say('The book could not be added.');
    return;
  }
  final problem = await addBookFile(
    library: library,
    files: files,
    booksDir: booksDir,
    bookId: bookId,
    picked: picked,
  );
  if (problem != null) {
    say(problem);
    return;
  }
  onLinked(bookId);
  final title = repository.byId(bookId)?.title ?? 'the book';
  messenger.showSnackBar(
    SnackBar(
      content: Text('Added "${picked.name}" to $title'),
      action: SnackBarAction(
        label: 'Read',
        onPressed: () {
          if (!context.mounted) return;
          openReader(
            context,
            repository: repository,
            library: library,
            bookId: bookId,
          );
        },
      ),
    ),
  );
}

/// Links audio files to a book as its audiobook: one file, or every file
/// of a folder (in name order). [folder] says the files came from one
/// folder, whose name then stands for the book.
Future<void> linkAudiobook(
  BuildContext context, {
  required BookRepository repository,
  required List<PickedFile> picked,
  required bool folder,
  required void Function(String bookId) onLinked,
}) async {
  final controller = Listening.controller;
  final files = Listening.files;
  if (controller == null || files == null) return;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final audio = [
    for (final file in picked)
      if (isAudioFileName(file.name)) file,
  ]..sort((a, b) => naturalCompare(a.name, b.name));
  if (audio.isEmpty) {
    say(folder
        ? 'There are no audio files in that folder.'
        : 'That is not an audio file Chapterly can play.');
    return;
  }
  // A folder is named after the book; a single file by its own name.
  final first = audio.first;
  final name = folder ? _folderName(first) : first.name;
  final source = files.open(first.location);
  final AudioTags tags;
  try {
    tags = await readAudioTags(source);
  } finally {
    await source.close();
  }
  if (!context.mounted) return;
  final choice = await _askWhichBook(
    context,
    repository: repository,
    fileName: name,
    found: FoundBookInfo(title: tags.bookTitle, author: tags.author),
    nameParts: fileNameParts(name),
    audio: true,
    hasFile: (id) => controller.library.linkFor(id) != null,
  );
  if (choice == null || !context.mounted) return;

  final link = await _withProgress(
    context,
    'Reading the audio files...',
    buildAudioLink(files, audio),
  );
  if (link == null) {
    say('That is not an audio file Chapterly can play.');
    return;
  }
  final bookId = await _bookFor(choice, repository, BookFormat.audiobook);
  if (bookId == null) {
    say('The book could not be added.');
    return;
  }
  final old = controller.library.linkFor(bookId);
  if (old != null) {
    if (controller.bookId == bookId) await controller.close();
    final kept = {for (final t in link.tracks) t.location};
    await files.release([
      for (final t in old.tracks)
        if (!kept.contains(t.location)) t.location,
    ]);
  }
  await controller.library.setLink(bookId, link);
  final book = repository.byId(bookId);
  if (book != null && book.format == null) {
    await repository.setFormat(bookId, BookFormat.audiobook);
  }
  onLinked(bookId);
  messenger.showSnackBar(
    SnackBar(
      content: Text('Added the audiobook to ${book?.title ?? 'the book'}'),
      action: SnackBarAction(
        label: 'Play',
        onPressed: () => controller.open(bookId),
      ),
    ),
  );
}

/// The folder a picked file came from, by name. Picked folder files are
/// named by their place inside the folder ("CD 1/01.mp3").
String _folderName(PickedFile file) {
  final location = file.location;
  final folder = location.length > file.name.length
      ? location.substring(0, location.length - file.name.length)
      : location;
  final parts = folder
      .split(RegExp(r'[\\/]'))
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? file.name : parts.last;
}

/// The title and author inside an EPUB or PDF. Empty when there is none or
/// the file cannot be read; the file name is then used.
///
/// A file on Windows is read where it is. On Android the picked file is a
/// content:// address that cannot be opened as a file, so a short-lived
/// copy is made in the books folder and deleted again.
Future<FoundBookInfo> _bookFileInfo(
  EbookFiles files,
  Directory booksDir,
  PickedFile picked,
  EbookFormat format,
) async {
  File? temporary;
  try {
    var file = File(picked.location);
    if (!await file.exists()) {
      await booksDir.create(recursive: true);
      temporary = File(
        '${booksDir.path}/probe-${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      final copied = await files.copy(picked, temporary.path);
      if (copied <= 0) return const FoundBookInfo();
      file = temporary;
    }
    if (await file.length() > _readLimit) return const FoundBookInfo();
    final bytes = await file.readAsBytes();
    final info = format == EbookFormat.epub
        ? epubTitleAndAuthor(bytes)
        : pdfTitleAndAuthor(bytes);
    if (info == null) return const FoundBookInfo();
    return FoundBookInfo(title: info.title, author: info.author);
  } catch (_) {
    return const FoundBookInfo();
  } finally {
    try {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    } catch (_) {
      // Left behind; it does no harm.
    }
  }
}

/// The id of the chosen book, adding it first when it is new.
Future<String?> _bookFor(
  LinkChoice choice,
  BookRepository repository,
  BookFormat format,
) async {
  final existing = choice.bookId;
  if (existing != null) return existing;
  await repository.add(
    title: choice.title,
    author: choice.author,
    shelf: choice.shelf,
    format: format,
  );
  // A new book goes first in the list.
  final added = repository.allBooks.firstOrNull;
  return added != null && added.title == choice.title ? added.id : null;
}

/// Shows a small "working" window while [work] runs.
Future<T> _withProgress<T>(
  BuildContext context,
  String message,
  Future<T> work,
) async {
  final navigator = Navigator.of(context);
  var shown = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  ).whenComplete(() => shown = false);
  try {
    return await work;
  } finally {
    if (shown) navigator.pop();
  }
}

Future<LinkChoice?> _askWhichBook(
  BuildContext context, {
  required BookRepository repository,
  required String fileName,
  required FoundBookInfo found,
  required List<String> nameParts,
  required bool audio,
  required bool Function(String bookId) hasFile,
}) {
  final books = repository.books;
  final matches = findMatchingBooks(
    books,
    title: found.title,
    author: found.author,
    nameParts: nameParts,
  );
  final guess = found.isEmpty
      ? guessFromFileName(fileName)
      : FoundBookInfo(title: found.title, author: found.author);
  return showDialog<LinkChoice>(
    context: context,
    builder: (_) => LinkFileDialog(
      fileName: fileName,
      found: found,
      books: books,
      matches: matches,
      newBook: guess,
      audio: audio,
      hasFile: hasFile,
    ),
  );
}

/// What to link a file to: a book in the library, or a new one.
class LinkChoice {
  const LinkChoice.existing(String this.bookId)
      : title = '',
        author = '',
        shelf = Shelf.inProgress;

  const LinkChoice.newBook({
    required this.title,
    required this.author,
    required this.shelf,
  }) : bookId = null;

  final String? bookId;
  final String title;
  final String author;
  final Shelf shelf;
}

/// Asks which book a file belongs to. The best match is already chosen
/// when it is clear; otherwise you pick one of the likely books, search
/// the library, or add the file as a new book.
class LinkFileDialog extends StatefulWidget {
  const LinkFileDialog({
    super.key,
    required this.fileName,
    required this.found,
    required this.books,
    required this.matches,
    required this.newBook,
    required this.audio,
    this.hasFile,
  });

  final String fileName;

  /// The title and author inside the file (empty when it has none).
  final FoundBookInfo found;

  /// The whole library, for searching.
  final List<Book> books;
  final List<BookMatch> matches;

  /// The title and author to start a new book with.
  final FoundBookInfo newBook;
  final bool audio;

  /// Whether a book already has a file of this kind (it gets replaced).
  final bool Function(String bookId)? hasFile;

  @override
  State<LinkFileDialog> createState() => _LinkFileDialogState();
}

class _LinkFileDialogState extends State<LinkFileDialog> {
  static const _newKey = '+new';

  final _search = TextEditingController();
  late final _title = TextEditingController(text: widget.newBook.title);
  late final _author = TextEditingController(text: widget.newBook.author);
  late final bool _sure = isSureMatch(widget.matches);
  late String? _selected = _sure
      ? widget.matches.first.book.id
      : (widget.matches.isEmpty ? _newKey : null);
  Shelf _shelf = Shelf.inProgress;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      _selected != null &&
      (_selected != _newKey || _title.text.trim().isNotEmpty);

  void _confirm() {
    if (!_canConfirm) return;
    final selected = _selected!;
    Navigator.of(context).pop(
      selected == _newKey
          ? LinkChoice.newBook(
              title: _title.text.trim(),
              author: _author.text.trim(),
              shelf: _shelf,
            )
          : LinkChoice.existing(selected),
    );
  }

  void _swap() {
    final title = _title.text;
    _title.text = _author.text;
    _author.text = title;
  }

  List<Book> _searchResults() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final shown = {for (final m in widget.matches) m.book.id};
    return [
      for (final book in widget.books)
        if (!shown.contains(book.id) &&
            (book.title.toLowerCase().contains(query) ||
                book.author.toLowerCase().contains(query)))
          book,
    ].take(6).toList();
  }

  Widget _choice({
    required String key,
    required String title,
    String? subtitle,
  }) {
    final selected = _selected == key;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      selected: selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => setState(() => _selected = key),
    );
  }

  Widget _bookChoice(Book book) {
    final replaces = widget.hasFile?.call(book.id) ?? false;
    return _choice(
      key: book.id,
      title: book.title,
      subtitle: [
        if (book.author.isNotEmpty) book.author,
        book.shelf.label,
        if (replaces)
          widget.audio
              ? 'has audio already; this replaces it'
              : 'has a book file already; this replaces it',
      ].join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final found = widget.found;
    final results = _searchResults();
    final heading = widget.matches.isEmpty
        ? 'No book in your library matches.'
        : (_sure ? 'This looks like:' : 'Is it one of these?');
    return AlertDialog(
      title: Text(widget.audio ? 'Add an audiobook' : 'Add a book to read'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fileName,
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (!found.isEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'In the file: ${found.title}'
                  '${found.author.isNotEmpty ? ' by ${found.author}' : ''}',
                  style: textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Text(heading, style: textTheme.titleSmall),
              for (final match in widget.matches) _bookChoice(match.book),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Find another book in your library',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              for (final book in results) _bookChoice(book),
              if (_search.text.trim().isNotEmpty && results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No books found', style: textTheme.bodySmall),
                ),
              const SizedBox(height: 8),
              _choice(
                key: _newKey,
                title: 'Add it as a new book',
                subtitle: _selected == _newKey ? null : 'To your library',
              ),
              if (_selected == _newKey) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _title,
                            decoration:
                                const InputDecoration(labelText: 'Title'),
                            onSubmitted: (_) => _confirm(),
                          ),
                          TextField(
                            controller: _author,
                            decoration:
                                const InputDecoration(labelText: 'Author'),
                            onSubmitted: (_) => _confirm(),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Swap title and author',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: _swap,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Chips wrap on a narrow phone screen; a segmented button would
                // not fit.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final shelf in const [
                      Shelf.forLater,
                      Shelf.inProgress,
                      Shelf.finished,
                    ])
                      ChoiceChip(
                        label: Text(shelf.label),
                        selected: _shelf == shelf,
                        onSelected: (_) => setState(() => _shelf = shelf),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: _sure,
          onPressed: _canConfirm ? _confirm : null,
          child: Text(_selected == _newKey ? 'Add and link' : 'Link'),
        ),
      ],
    );
  }
}
