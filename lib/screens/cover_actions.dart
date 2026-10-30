import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../data/book_repository.dart';
import '../data/cover_image.dart';

/// The books open on screen, newest last. A picture dropped on the window
/// or pasted with Ctrl+V becomes the cover of the last one.
class ShownBooks {
  ShownBooks._();

  static final _ids = <String>[];

  /// The book a dropped or pasted picture is for, or null when none is open.
  static String? get current => _ids.isEmpty ? null : _ids.last;

  static void _add(String id) => _ids.add(id);

  static void _remove(String id) {
    final at = _ids.lastIndexOf(id);
    if (at >= 0) _ids.removeAt(at);
  }
}

/// Marks [bookId] as open on screen while this widget is shown.
class ShownBook extends StatefulWidget {
  const ShownBook({super.key, required this.bookId, required this.child});

  final String bookId;
  final Widget child;

  @override
  State<ShownBook> createState() => _ShownBookState();
}

class _ShownBookState extends State<ShownBook> {
  @override
  void initState() {
    super.initState();
    ShownBooks._add(widget.bookId);
  }

  @override
  void didUpdateWidget(ShownBook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      ShownBooks._remove(oldWidget.bookId);
      ShownBooks._add(widget.bookId);
    }
  }

  @override
  void dispose() {
    ShownBooks._remove(widget.bookId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Makes the picture in [bytes] the cover of [bookId], with Undo.
Future<void> useCoverPicture(
  ScaffoldMessengerState? messenger,
  BookRepository repository,
  String bookId,
  Uint8List bytes,
) async {
  final book = repository.byId(bookId);
  if (book == null) return;
  final cover = await makeDataCover(bytes);
  if (cover == null) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('That file is not a picture Chapterly can read.'),
      ),
    );
    return;
  }
  final before = book.coverUrl;
  await repository.setCover(bookId, cover);
  messenger?.showSnackBar(
    SnackBar(
      content: Text('New cover for "${book.title}"'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => repository.setCover(bookId, before),
      ),
    ),
  );
}

/// Asks for a picture file and makes it the cover of [bookId].
Future<void> pickCoverFile(
  ScaffoldMessengerState? messenger,
  BookRepository repository,
  String bookId,
) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Pictures', extensions: coverExtensions),
    ],
  );
  if (file == null) return;
  await useCoverPicture(messenger, repository, bookId, await file.readAsBytes());
}

/// Makes the picture on the clipboard (or a copied picture file) the cover
/// of [bookId]. Says so when there is no picture.
Future<void> pasteCover(
  ScaffoldMessengerState? messenger,
  BookRepository repository,
  String bookId,
) async {
  Uint8List? bytes;
  try {
    bytes = await Pasteboard.image;
    if (bytes == null) {
      for (final path in await Pasteboard.files()) {
        if (isCoverImageFile(path)) {
          bytes = await File(path).readAsBytes();
          break;
        }
      }
    }
  } catch (_) {
    bytes = null;
  }
  if (bytes == null) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('There is no picture on the clipboard. Copy one first.'),
      ),
    );
    return;
  }
  await useCoverPicture(messenger, repository, bookId, bytes);
}

bool _typingInTextField() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return focused.widget is EditableText ||
      focused.findAncestorStateOfType<EditableTextState>() != null;
}

/// Ctrl+V anywhere outside a text field pastes a picture as the cover of the
/// book that is open. Wraps the whole app.
class CoverPasteShortcut extends StatelessWidget {
  const CoverPasteShortcut({
    super.key,
    required this.repository,
    required this.messengerKey,
    required this.child,
  });

  final BookRepository repository;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.keyV ||
            !HardwareKeyboard.instance.isControlPressed ||
            _typingInTextField()) {
          return KeyEventResult.ignored;
        }
        final id = ShownBooks.current;
        if (id == null) return KeyEventResult.ignored;
        pasteCover(messengerKey.currentState, repository, id);
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
