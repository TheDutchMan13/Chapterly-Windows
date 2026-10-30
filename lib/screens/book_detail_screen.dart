import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/collections.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/rating_text.dart';
import '../data/statistics.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/rating_aspect.dart';
import '../models/reading.dart';
import '../models/shelf.dart';
import '../models/wish_priority.dart';
import '../widgets/book_cover.dart';
import 'author_books_screen.dart';
import 'book_card_screen.dart';
import 'log_entry_dialog.dart';
import 'next_up_screen.dart';
import 'similar_books_screen.dart';
import 'subject_books_screen.dart';

/// Shows one book. Change its shelf, format, rating, dates, pages, tags,
/// notes, keep a reading log, read it again, or move it to the trash.
class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
    required this.bookId,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;
  final String bookId;

  /// Shows a dialog with one text field. Returns the text, or null if cancelled.
  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String initial,
    String? label,
    String? helper,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: maxLines == 1 ? 1 : 3,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          decoration: InputDecoration(labelText: label, helperText: helper),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editTags(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Edit tags',
      initial: book.tags.join(', '),
      label: 'Tags',
      helper: 'Separate with commas',
    );
    if (text == null) return;
    await repository.setTags(book.id, parseTags(text));
  }

  Future<void> _editPages(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Number of pages',
      initial: book.pages?.toString() ?? '',
      label: 'Pages',
      helper: 'Leave empty to clear',
      keyboardType: TextInputType.number,
      formatters: [FilteringTextInputFormatter.digitsOnly],
    );
    if (text == null) return;
    final pages = int.tryParse(text.trim());
    await repository.setPages(book.id, pages != null && pages > 0 ? pages : null);
  }

  Future<void> _editCurrentPage(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Current page',
      initial: book.currentPage?.toString() ?? '',
      label: 'Page you are on',
      helper: book.pages == null
          ? 'Leave empty to clear'
          : 'Out of ${book.pages}. Leave empty to clear',
      keyboardType: TextInputType.number,
      formatters: [FilteringTextInputFormatter.digitsOnly],
    );
    if (text == null) return;
    await repository.setCurrentPage(book.id, int.tryParse(text.trim()));
  }

  Future<void> _editPriority(BuildContext context, Book book) async {
    final choice = await showDialog<List<WishPriority?>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Priority'),
        children: [
          for (final priority in WishPriority.values.reversed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop([priority]),
              child: Text(priority.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop([null]),
            child: const Text('Not set'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await repository.setPriority(book.id, choice.first);
  }

  Future<void> _editBuyAt(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Where to get it',
      initial: book.buyAt ?? '',
      label: 'Shop, library or web link',
      helper: 'For example "Library" or a web address. Leave empty to clear',
    );
    if (text == null) return;
    await repository.setBuyAt(book.id, text);
  }

  Future<void> _openBuyLink(BuildContext context, Book book) async {
    final link = book.buyLink;
    if (link == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(link, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  void _openNextUp(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NextUpScreen(
          repository: repository,
          settings: settings,
          fileIo: fileIo,
        ),
      ),
    );
  }

  List<Widget> _wishlistTiles(BuildContext context, Book book) {
    final queue = repository.nextUp;
    final place = queue.indexWhere((other) => other.id == book.id);
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.flag_outlined),
        title: const Text('Priority'),
        subtitle: Text(book.priority?.label ?? 'Not set'),
        onTap: () => _editPriority(context, book),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.storefront_outlined),
        title: const Text('Where to get it'),
        subtitle: Text(book.buyAt ?? 'Not set'),
        trailing: book.buyLink == null
            ? null
            : IconButton(
                tooltip: 'Open link',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openBuyLink(context, book),
              ),
        onTap: () => _editBuyAt(context, book),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.format_list_numbered),
        title: const Text('Next up'),
        subtitle: Text(
          place < 0 ? 'Not in the queue' : 'Number ${place + 1} of ${queue.length}',
        ),
        trailing: place > 0
            ? IconButton(
                tooltip: 'Read this next',
                icon: const Icon(Icons.vertical_align_top),
                onPressed: () => repository.moveToTopOfQueue(book.id),
              )
            : null,
        onTap: () => _openNextUp(context),
      ),
    ];
  }

  String _progressText(Book book) {
    final page = book.currentPage;
    final progress = book.progress;
    final percent = progress == null ? '' : ' (${(progress * 100).round()}%)';
    if (page == null) {
      final logged = book.progressPage;
      return logged == null
          ? 'Not set'
          : 'About page $logged, from your reading log$percent';
    }
    final total = book.pages;
    return total == null ? 'Page $page' : 'Page $page of $total$percent';
  }

  String _aspectSummary(Book book) => [
        for (final aspect in RatingAspect.values)
          if (book.aspectRatings[aspect.name] case final value?)
            '${aspect.label} $value',
      ].join(' · ');

  Future<void> _editNotes(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Notes and review',
      initial: book.notes ?? '',
      label: 'Your thoughts',
      helper: 'Leave empty to clear',
      maxLines: 8,
    );
    if (text == null) return;
    await repository.setNotes(book.id, text);
  }

  Future<void> _pickDate(
    BuildContext context,
    Book book, {
    required bool start,
  }) async {
    final current = start ? book.startedAt : book.finishedAt;
    final first = DateTime(1950);
    final last = DateTime.now().add(const Duration(days: 1));
    var initial = current ?? DateTime.now();
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(first)) initial = first;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !context.mounted) return;

    final startedAt = start ? picked : book.startedAt;
    final finishedAt = start ? book.finishedAt : picked;
    if (startedAt != null &&
        finishedAt != null &&
        finishedAt.isBefore(startedAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The finish date cannot be before the start date.'),
        ),
      );
      return;
    }
    await repository.setDates(
      book.id,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }

  Future<void> _addLogEntry(BuildContext context, Book book) async {
    final amounts = await showLogEntryDialog(context);
    if (amounts == null) return;
    await repository.addLogEntry(
      book.id,
      DateTime.now(),
      amounts.pages,
      minutes: amounts.minutes,
    );
  }

  Future<void> _readAgain(BuildContext context, Book book) async {
    var start = DateTime.now();
    final chosen = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Read again?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This reading is saved under "Earlier readings". The book '
                'moves to In progress.',
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Started ${formatDate(start)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: start,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => start = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(start),
              child: const Text('Read again'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await repository.readAgain(book.id, startedAt: chosen);
  }

  Future<void> _editSeries(BuildContext context, Book book) async {
    final name = TextEditingController(text: book.series ?? '');
    final number =
        TextEditingController(text: book.seriesNumber?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Series'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Series name',
                helperText: 'Leave empty to remove',
              ),
            ),
            TextField(
              controller: number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Book number'),
            ),
          ],
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
    final nameText = name.text;
    final numberValue = int.tryParse(number.text.trim());
    name.dispose();
    number.dispose();
    if (saved != true) return;
    await repository.setSeries(
      book.id,
      nameText,
      numberValue != null && numberValue > 0 ? numberValue : null,
    );
  }

  void _openBook(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: repository,
          settings: settings,
          fileIo: fileIo,
          bookId: book.id,
        ),
      ),
    );
  }

  void _openCard(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookCardScreen(book: book, fileIo: fileIo),
      ),
    );
  }

  Future<void> _trash(BuildContext context, Book book) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await repository.moveToTrash(book.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('"${book.title}" moved to the trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.restore(book.id),
        ),
      ),
    );
  }

  void _showSimilar(
    BuildContext context, {
    required String title,
    required bool Function(Book) test,
    int Function(Book, Book)? compare,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimilarBooksScreen(
          repository: repository,
          settings: settings,
          fileIo: fileIo,
          title: title,
          test: test,
          compare: compare,
        ),
      ),
    );
  }

  Future<void> _addQuote(BuildContext context, Book book) async {
    final text = TextEditingController();
    final page = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a quote'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Quote'),
              ),
              TextField(
                controller: page,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Page (optional)'),
              ),
            ],
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
    final quoteText = text.text;
    final pageNumber = int.tryParse(page.text.trim());
    text.dispose();
    page.dispose();
    if (saved != true) return;
    await repository.addQuote(book.id, quoteText, page: pageNumber);
  }

  Future<void> _newShelf(BuildContext context, Book book) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New shelf'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Shelf name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) return;
    settings.addCollection(clean);
    await repository.addToCollectionAll({book.id}, clean);
  }

  Future<void> _toggleShelf(Book book, String name, {required bool on}) {
    final names = [
      for (final c in book.collections)
        if (c != name) c,
      if (on) name,
    ];
    return repository.setCollections(book.id, names);
  }

  void _openSubjectBooks(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubjectBooksScreen(
          repository: repository,
          client: OpenLibraryClient(),
          settings: settings,
          book: book,
        ),
      ),
    );
  }

  void _openAuthorBooks(BuildContext context, String author) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthorBooksScreen(
          repository: repository,
          client: OpenLibraryClient(),
          author: author,
          settings: settings,
        ),
      ),
    );
  }

  Widget _dateTile(BuildContext context, Book book, {required bool start}) {
    final date = start ? book.startedAt : book.finishedAt;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        start ? Icons.play_circle_outline : Icons.check_circle_outline,
      ),
      title: Text(start ? 'Started' : 'Finished'),
      subtitle: Text(date == null ? 'Not set' : formatDate(date)),
      trailing: date == null
          ? null
          : IconButton(
              tooltip: 'Clear date',
              icon: const Icon(Icons.clear),
              onPressed: () => repository.setDates(
                book.id,
                startedAt: start ? null : book.startedAt,
                finishedAt: start ? book.finishedAt : null,
              ),
            ),
      onTap: () => _pickDate(context, book, start: start),
    );
  }

  String _logLine(LogEntry entry) {
    final amounts = [
      if (entry.pages > 0) '${entry.pages} pages',
      if (entry.minutes > 0) formatMinutes(entry.minutes),
    ].join(' · ');
    return '${formatDate(entry.date)}: $amounts';
  }

  String _readingSummary(Reading reading) {
    final started = reading.startedAt;
    final finished = reading.finishedAt;
    final dates = [
      if (started != null) formatDate(started),
      if (finished != null) formatDate(finished),
    ].join(' → ');
    return [
      if (dates.isNotEmpty) dates else 'No dates',
      if (reading.rating != null)
        ratingText(reading.rating!, asNumber: settings.ratingAsNumber),
    ].join(' · ');
  }

  Future<void> _rate(BuildContext context, Book book) async {
    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Your rating'),
        children: [
          for (var value = 5; value >= 1; value--)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(
                ratingText(value, asNumber: settings.ratingAsNumber),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('No rating'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await repository.setRating(book.id, choice == 0 ? null : choice);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repository, settings]),
      builder: (context, _) {
        final book = repository.byId(bookId);
        if (book == null) return const Scaffold(body: SizedBox.shrink());
        final textTheme = Theme.of(context).textTheme;
        final loggedPages =
            book.readingLog.fold<int>(0, (sum, entry) => sum + entry.pages);
        final loggedMinutes =
            book.readingLog.fold<int>(0, (sum, entry) => sum + entry.minutes);
        final author = book.author;
        final pace = readingPace(book);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Book'),
            actions: [
              IconButton(
                tooltip: 'Share a book card',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _openCard(context, book),
              ),
              IconButton(
                tooltip: book.favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  book.favorite ? Icons.favorite : Icons.favorite_border,
                  color: book.favorite ? Colors.redAccent : null,
                ),
                onPressed: () =>
                    repository.setFavorite(book.id, favorite: !book.favorite),
              ),
              IconButton(
                tooltip: 'Move to trash',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _trash(context, book),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: BookCover(
                  coverUrl: book.coverUrl,
                  width: 120,
                  height: 180,
                ),
              ),
              const SizedBox(height: 16),
              Text(book.title, style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              if (author.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _showSimilar(
                      context,
                      title: 'More by $author',
                      test: (other) =>
                          other.author.toLowerCase() == author.toLowerCase(),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: Text(author),
                  ),
                ),
              if (author.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _openAuthorBooks(context, author),
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('More by this author online'),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => _openSubjectBooks(context, book),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Books like this online'),
                ),
              ),
              if (book.firstPublishYear != null)
                Text('First published ${book.firstPublishYear}'),
              if (book.isbn != null) Text('ISBN ${book.isbn}'),
              const SizedBox(height: 24),
              DropdownButtonFormField<Shelf>(
                initialValue: book.shelf,
                decoration: const InputDecoration(labelText: 'Shelf'),
                items: [
                  for (final shelf in Shelf.values)
                    DropdownMenuItem(value: shelf, child: Text(shelf.label)),
                ],
                onChanged: (value) {
                  if (value != null) repository.moveTo(book.id, value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<BookFormat?>(
                initialValue: book.format,
                decoration: const InputDecoration(labelText: 'Format'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final format in BookFormat.values)
                    DropdownMenuItem(value: format, child: Text(format.label)),
                ],
                onChanged: (value) => repository.setFormat(book.id, value),
              ),
              const SizedBox(height: 24),
              if (settings.ratingAsNumber)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Your rating'),
                  subtitle: Text(
                    book.rating == null
                        ? 'Not rated'
                        : ratingText(book.rating!, asNumber: true),
                  ),
                  onTap: () => _rate(context, book),
                )
              else ...[
                Text('Your rating', style: textTheme.titleMedium),
                Row(
                  children: [
                    for (var star = 1; star <= 5; star++)
                      IconButton(
                        tooltip: '$star of 5',
                        icon: Icon(
                          star <= (book.rating ?? 0)
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () => repository.setRating(
                          book.id,
                          book.rating == star ? null : star,
                        ),
                      ),
                  ],
                ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Rating details'),
                subtitle: Text(
                  book.aspectRatings.isEmpty
                      ? 'Rate the plot, characters, writing and pacing'
                      : _aspectSummary(book),
                ),
                children: [
                  for (final aspect in RatingAspect.values)
                    Row(
                      children: [
                        Expanded(child: Text(aspect.label)),
                        for (var star = 1; star <= 5; star++)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 22,
                            tooltip: '${aspect.label}: $star of 5',
                            icon: Icon(
                              star <= (book.aspectRatings[aspect.name] ?? 0)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                            ),
                            onPressed: () => repository.setAspectRating(
                              book.id,
                              aspect,
                              book.aspectRatings[aspect.name] == star
                                  ? null
                                  : star,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _dateTile(context, book, start: true),
              _dateTile(context, book, start: false),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Pages'),
                subtitle: Text(book.pages?.toString() ?? 'Not set'),
                onTap: () => _editPages(context, book),
              ),
              if (book.shelf == Shelf.forLater) ..._wishlistTiles(context, book),
              if (book.shelf == Shelf.inProgress)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_outline),
                  title: const Text('Current page'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_progressText(book)),
                      if (book.progress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(value: book.progress),
                        ),
                      if (pace != null && book.readingLog.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Pace: ${pace.describe()}'),
                        ),
                    ],
                  ),
                  onTap: () => _editCurrentPage(context, book),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: const Text('Series'),
                subtitle: Text(
                  book.series == null
                      ? 'Not set'
                      : book.seriesNumber == null
                          ? book.series!
                          : '${book.series} #${book.seriesNumber}',
                ),
                onTap: () => _editSeries(context, book),
              ),
              if (book.series != null)
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.list, size: 18),
                      label: const Text('Show the series'),
                      onPressed: () => _showSimilar(
                        context,
                        title: book.series!,
                        test: (other) =>
                            other.series?.trim().toLowerCase() ==
                            book.series!.trim().toLowerCase(),
                        compare: (a, b) =>
                            (a.seriesNumber ?? 1 << 30)
                                .compareTo(b.seriesNumber ?? 1 << 30),
                      ),
                    ),
                    if (repository.nextInSeries(book) != null)
                      ActionChip(
                        avatar: const Icon(Icons.skip_next, size: 18),
                        label: Text(
                          'Next: ${repository.nextInSeries(book)!.title}',
                        ),
                        onPressed: () =>
                            _openBook(context, repository.nextInSeries(book)!),
                      ),
                  ],
                ),
              if (book.shelf == Shelf.finished)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _readAgain(context, book),
                    icon: const Icon(Icons.replay),
                    label: const Text('Read again'),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Notes', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editNotes(context, book),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ],
              ),
              Text(book.notes ?? 'No notes yet.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Reading log', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _addLogEntry(context, book),
                    icon: const Icon(Icons.add),
                    label: const Text('Add to log'),
                  ),
                ],
              ),
              if (book.readingLog.isEmpty)
                const Text(
                  'Write down pages or minutes you read to see them in your '
                  'statistics.',
                )
              else ...[
                Text(
                  [
                    if (loggedPages > 0) '$loggedPages pages',
                    if (loggedMinutes > 0) formatMinutes(loggedMinutes),
                  ].join(' · '),
                ),
                if (pace != null) Text('Pace: ${pace.describe()}'),
                for (var i = 0; i < book.readingLog.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(_logLine(book.readingLog[i])),
                    trailing: IconButton(
                      tooltip: 'Remove entry',
                      icon: const Icon(Icons.clear),
                      onPressed: () => repository.removeLogEntry(book.id, i),
                    ),
                  ),
              ],
              if (book.previousReadings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Earlier readings', style: textTheme.titleMedium),
                for (var i = 0; i < book.previousReadings.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(_readingSummary(book.previousReadings[i])),
                    trailing: IconButton(
                      tooltip: 'Remove this reading',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          repository.removePreviousReading(book.id, i),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Tags', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editTags(context, book),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ],
              ),
              if (book.tags.isEmpty)
                const Text('No tags yet.')
              else
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tag in book.tags)
                      ActionChip(
                        label: Text(tag),
                        tooltip: 'Show books with this tag',
                        onPressed: () => _showSimilar(
                          context,
                          title: 'Tagged "$tag"',
                          test: (other) => other.tags.contains(tag),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('Shelves', style: textTheme.titleMedium),
              ListenableBuilder(
                listenable: settings,
                builder: (context, _) => Wrap(
                  spacing: 8,
                  children: [
                    for (final name in {
                      ...allCollectionNames(settings, repository),
                      ...book.collections,
                    })
                      FilterChip(
                        label: Text(name),
                        selected: book.collections.contains(name),
                        onSelected: (on) => _toggleShelf(book, name, on: on),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('New shelf'),
                      onPressed: () => _newShelf(context, book),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Quotes', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _addQuote(context, book),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              if (book.quotes.isEmpty)
                const Text('No quotes saved yet.')
              else
                for (var i = 0; i < book.quotes.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '\u201c${book.quotes[i].text}\u201d',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    subtitle: book.quotes[i].page == null
                        ? null
                        : Text('Page ${book.quotes[i].page}'),
                    trailing: IconButton(
                      tooltip: 'Remove quote',
                      icon: const Icon(Icons.clear),
                      onPressed: () => repository.removeQuote(book.id, i),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
