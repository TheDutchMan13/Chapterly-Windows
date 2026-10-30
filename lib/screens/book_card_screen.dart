import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/file_io.dart';
import '../models/book.dart';
import '../widgets/book_cover.dart';

/// A picture of a book (cover, title, rating and a quote from your notes)
/// that can be shared as an image.
class BookCardScreen extends StatefulWidget {
  const BookCardScreen({super.key, required this.book, required this.fileIo});

  final Book book;
  final FileIo fileIo;

  @override
  State<BookCardScreen> createState() => _BookCardScreenState();
}

class _BookCardScreenState extends State<BookCardScreen> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  String? get _quote {
    final notes = widget.book.notes?.trim();
    if (notes == null || notes.isEmpty) return null;
    return notes.length <= 220 ? notes : '${notes.substring(0, 220).trimRight()}…';
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('No image data');
      await widget.fileIo.shareImage(
        fileName: 'chapterly-book-card.png',
        bytes: data.buffer.asUint8List(),
        subject: widget.book.title,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not make the picture.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final quote = _quote;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share a book card'),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: _busy ? null : _share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                color: scheme.primaryContainer,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BookCover(
                      coverUrl: book.coverUrl,
                      width: 140,
                      height: 210,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      book.title,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    if (book.author.isNotEmpty)
                      Text(
                        book.author,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    if (book.rating != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var star = 1; star <= 5; star++)
                            Icon(
                              star <= book.rating!
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                            ),
                        ],
                      ),
                    ],
                    if (quote != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        '“$quote”',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Chapterly',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'The quote comes from your notes. Edit the notes on the book '
            'screen to change it.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
