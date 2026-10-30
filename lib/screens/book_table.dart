import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../data/rating_text.dart';
import '../data/table_columns.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';

const _rowHeight = 44.0;
const _checkWidth = 48.0;

/// The library as a table: one book per row, sortable columns, and cells you
/// can change in place. Double-click a title, author or page count to type;
/// click a shelf, rating or format to pick one. Ctrl+click and Shift+click
/// select several books.
class BookTable extends StatefulWidget {
  const BookTable({
    super.key,
    required this.books,
    required this.repository,
    required this.selected,
    required this.onSetSelected,
    required this.onOpen,
    required this.onContextMenu,
    required this.ratingAsNumber,
    required this.emptyText,
  });

  /// The books to show, in the library's sort order.
  final List<Book> books;
  final BookRepository repository;
  final Set<String> selected;
  final void Function(Set<String> ids) onSetSelected;
  final void Function(Book book) onOpen;
  final void Function(Book book, Offset position) onContextMenu;
  final bool ratingAsNumber;
  final String emptyText;

  @override
  State<BookTable> createState() => _BookTableState();
}

class _BookTableState extends State<BookTable> {
  TableColumn? _sortColumn;
  bool _ascending = true;
  String? _anchorId;
  (String, TableColumn)? _editing;
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(() {
      if (!_editorFocus.hasFocus && _editing != null) _commit();
    });
  }

  @override
  void dispose() {
    _editor.dispose();
    _editorFocus.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  List<Book> get _rows {
    final column = _sortColumn;
    if (column == null) return widget.books;
    return sortByColumn(widget.books, column, ascending: _ascending);
  }

  void _sortBy(TableColumn column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _ascending = true;
      } else if (_ascending) {
        _ascending = false;
      } else {
        // A third click goes back to the library's own order.
        _sortColumn = null;
      }
    });
  }

  void _tapRow(Book book, List<Book> rows) {
    final keys = HardwareKeyboard.instance;
    final selected = {...widget.selected};
    if (keys.isShiftPressed && _anchorId != null) {
      final from = rows.indexWhere((b) => b.id == _anchorId);
      final to = rows.indexOf(book);
      if (from >= 0 && to >= 0) {
        final start = from < to ? from : to;
        final end = from < to ? to : from;
        for (var i = start; i <= end; i++) {
          selected.add(rows[i].id);
        }
        widget.onSetSelected(selected);
        return;
      }
    }
    if (keys.isControlPressed || selected.isNotEmpty) {
      if (!selected.add(book.id)) selected.remove(book.id);
      _anchorId = book.id;
      widget.onSetSelected(selected);
      return;
    }
    _anchorId = book.id;
    widget.onOpen(book);
  }

  void _toggle(Book book) {
    final selected = {...widget.selected};
    if (!selected.add(book.id)) selected.remove(book.id);
    _anchorId = book.id;
    widget.onSetSelected(selected);
  }

  void _toggleAll(List<Book> rows) {
    final all =
        rows.isNotEmpty && rows.every((b) => widget.selected.contains(b.id));
    widget.onSetSelected(all ? {} : {for (final b in rows) b.id});
  }

  void _startEditing(Book book, TableColumn column) {
    final text = switch (column) {
      TableColumn.title => book.title,
      TableColumn.author => book.author,
      TableColumn.pages => book.pages?.toString() ?? '',
      _ => '',
    };
    setState(() {
      _editing = (book.id, column);
      _editor.text = text;
      _editor.selection =
          TextSelection(baseOffset: 0, extentOffset: text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocus.requestFocus();
    });
  }

  void _cancelEditing() => setState(() => _editing = null);

  Future<void> _commit() async {
    final editing = _editing;
    if (editing == null) return;
    final (id, column) = editing;
    final text = _editor.text.trim();
    setState(() => _editing = null);
    final repository = widget.repository;
    switch (column) {
      case TableColumn.title:
        await repository.setTitle(id, text);
      case TableColumn.author:
        await repository.setAuthorAll({id}, text);
      case TableColumn.pages:
        final pages = int.tryParse(text);
        await repository.setPages(id, pages != null && pages > 0 ? pages : null);
      default:
        break;
    }
  }

  Future<void> _pick(Book book, TableColumn column, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final where = RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final repository = widget.repository;
    switch (column) {
      case TableColumn.shelf:
        final shelf = await showMenu<Shelf>(
          context: context,
          position: where,
          items: [
            for (final shelf in Shelf.values)
              CheckedPopupMenuItem(
                value: shelf,
                checked: shelf == book.shelf,
                child: Text(shelf.label),
              ),
          ],
        );
        if (shelf != null && shelf != book.shelf) {
          await repository.moveTo(book.id, shelf);
        }
      case TableColumn.rating:
        final choice = await showMenu<int>(
          context: context,
          position: where,
          items: [
            for (var stars = 5; stars >= 1; stars--)
              CheckedPopupMenuItem(
                value: stars,
                checked: book.rating == stars,
                child: Text(ratingText(stars, asNumber: widget.ratingAsNumber)),
              ),
            const PopupMenuItem(value: 0, child: Text('No rating')),
          ],
        );
        if (choice != null) {
          await repository.setRating(book.id, choice == 0 ? null : choice);
        }
      case TableColumn.format:
        final choice = await showMenu<int>(
          context: context,
          position: where,
          items: [
            for (final format in BookFormat.values)
              CheckedPopupMenuItem(
                value: format.index,
                checked: book.format == format,
                child: Text(format.label),
              ),
            const PopupMenuItem(value: -1, child: Text('Not set')),
          ],
        );
        if (choice != null) {
          await repository.setFormat(
            book.id,
            choice < 0 ? null : BookFormat.values[choice],
          );
        }
      default:
        break;
    }
  }

  Map<TableColumn, double> _widths(double available) {
    final widths = {for (final c in TableColumn.values) c: c.width};
    final total = widths.values.fold<double>(_checkWidth, (a, b) => a + b);
    if (available > total) {
      widths[TableColumn.title] = TableColumn.title.width + available - total;
    }
    return widths;
  }

  Widget _header(Map<TableColumn, double> widths, List<Book> rows) {
    final theme = Theme.of(context);
    final allSelected =
        rows.isNotEmpty && rows.every((b) => widget.selected.contains(b.id));
    final someSelected = rows.any((b) => widget.selected.contains(b.id));
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _checkWidth,
            child: Checkbox(
              tristate: true,
              value: allSelected ? true : (someSelected ? null : false),
              onChanged: (_) => _toggleAll(rows),
            ),
          ),
          for (final column in TableColumn.values)
            InkWell(
              onTap: () => _sortBy(column),
              child: SizedBox(
                width: widths[column],
                height: _rowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          column.label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      if (_sortColumn == column)
                        Icon(
                          _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(Book book, TableColumn column, double width) {
    final theme = Theme.of(context);
    final editing = _editing;
    if (editing != null && editing.$1 == book.id && editing.$2 == column) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _cancelEditing,
            },
            child: TextField(
              controller: _editor,
              focusNode: _editorFocus,
              keyboardType: column == TableColumn.pages
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: column == TableColumn.pages
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
        ),
      );
    }
    final text = cellText(
      book,
      column,
      date: formatDate,
      rating: (stars) => ratingText(stars, asNumber: widget.ratingAsNumber),
    );
    Widget content = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: column == TableColumn.title
          ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)
          : theme.textTheme.bodyMedium,
    );
    if (column == TableColumn.title) {
      content = Row(
        children: [
          BookCover(coverUrl: book.coverUrl, width: 24, height: 34),
          const SizedBox(width: 8),
          if (book.favorite)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.favorite, size: 14, color: Colors.redAccent),
            ),
          Expanded(child: content),
        ],
      );
    }
    if (column.pickable) {
      content = Row(
        children: [
          Expanded(child: content),
          Icon(Icons.arrow_drop_down, size: 18, color: theme.hintColor),
        ],
      );
    }
    final cell = SizedBox(
      width: width,
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(alignment: Alignment.centerLeft, child: content),
      ),
    );
    if (column.pickable) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _pick(book, column, details.globalPosition),
        child: Tooltip(
          message: 'Click to change',
          waitDuration: const Duration(milliseconds: 800),
          child: cell,
        ),
      );
    }
    if (column.typable) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () => _startEditing(book, column),
        child: cell,
      );
    }
    return cell;
  }

  Widget _row(
    Book book,
    int index,
    List<Book> rows,
    Map<TableColumn, double> widths,
  ) {
    final theme = Theme.of(context);
    final isSelected = widget.selected.contains(book.id);
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : index.isOdd
              ? theme.colorScheme.surfaceContainerLowest
              : theme.colorScheme.surface,
      child: InkWell(
        onTap: () => _tapRow(book, rows),
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(book, details.globalPosition),
        child: Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _checkWidth,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggle(book),
                ),
              ),
              for (final column in TableColumn.values)
                _cell(book, column, widths[column]!),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(widget.emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _widths(constraints.maxWidth);
        final total = widths.values.fold<double>(_checkWidth, (a, b) => a + b);
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: total > constraints.maxWidth,
          notificationPredicate: (notification) => notification.depth == 0,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: total,
              child: Column(
                children: [
                  _header(widths, rows),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      child: ListView.builder(
                        controller: _vertical,
                        itemExtent: _rowHeight,
                        itemCount: rows.length,
                        itemBuilder: (context, index) =>
                            _row(rows[index], index, rows, widths),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
