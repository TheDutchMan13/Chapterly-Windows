import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';

/// The book you are reading, big at the top of the library, so carrying on
/// is one tap away.
class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({super.key, required this.book, required this.onOpen});

  final Book book;
  final void Function(Book book) onOpen;

  /// The book on In progress that changed last, or null when nothing is
  /// being read.
  static Book? pick(Iterable<Book> books) {
    Book? best;
    for (final book in books) {
      if (book.deletedAt != null || book.shelf != Shelf.inProgress) continue;
      if (best == null || book.updatedAt.isAfter(best.updatedAt)) best = book;
    }
    return best;
  }

  static Widget? forLibrary(
    Iterable<Book> books, {
    required void Function(Book book) onOpen,
  }) {
    final book = pick(books);
    if (book == null) return null;
    return ContinueReadingCard(book: book, onOpen: onOpen);
  }

  /// What the progress line says, and how far along as 0 to 1.
  static (String, double?) progressOf(Book book) {
    final read = book.progress;
    final page = book.progressPage;
    final pages = book.pages;
    if (read != null && page != null && pages != null) {
      return ('Page $page of $pages', read);
    }
    final listened = book.audio?.fraction;
    if (listened != null) return ('Listened so far', listened);
    if (pages != null) return ('$pages pages', null);
    return ('Just started', null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final (label, fraction) = progressOf(book);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: InkWell(
        onTap: () => onOpen(book),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              BookCover(
                coverUrl: book.coverUrl,
                title: book.title,
                width: 60,
                height: 90,
                shadow: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE READING',
                      style: text.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    if (book.author.isNotEmpty)
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (fraction != null) ...[
                const SizedBox(width: 8),
                _ProgressRing(fraction: fraction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      label: '$percent percent',
      excludeSemantics: true,
      child: SizedBox(
        width: 52,
        height: 52,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: fraction.clamp(0.0, 1.0),
            track: scheme.outlineVariant,
            fill: scheme.primary,
          ),
          child: Center(
            child: Text(
              '$percent%',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.fill});

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(ring, 0, math.pi * 2, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        paint..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}
