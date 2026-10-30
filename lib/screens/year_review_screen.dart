import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/year_review.dart';
import '../widgets/share_card.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A summary of one year of reading, as a card that can be shared as a picture.
class YearReviewScreen extends StatefulWidget {
  const YearReviewScreen({
    super.key,
    required this.repository,
    required this.fileIo,
    required this.year,
  });

  final BookRepository repository;
  final FileIo fileIo;
  final int year;

  @override
  State<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends State<YearReviewScreen> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await shareBoundaryAsImage(
        _cardKey,
        widget.fileIo,
        fileName: 'chapterly-${widget.year}-in-books.png',
        subject: 'My ${widget.year} in books',
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

  Widget _number(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: textTheme.headlineMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final onCard = textTheme.bodyMedium?.copyWith(
      color: scheme.onPrimaryContainer,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.year} in review'),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: _busy ? null : _share,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) {
          final review = computeYearReview(widget.repository.books, widget.year);
          final stats = review.stats;
          final author =
              stats.topAuthors.isEmpty ? null : stats.topAuthors.first;
          final tag = stats.topTags.isEmpty ? null : stats.topTags.first;
          final month = review.busiestMonth;
          final average = stats.averageRating;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: Container(
                    width: 340,
                    padding: const EdgeInsets.all(24),
                    color: scheme.primaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'My ${widget.year} in books',
                          style: textTheme.titleLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _number(
                              context,
                              '${stats.finishedCount}',
                              stats.finishedCount == 1 ? 'book' : 'books',
                            ),
                            _number(context, '${stats.pagesRead}', 'pages'),
                            _number(
                              context,
                              stats.loggedMinutes > 0
                                  ? formatMinutes(stats.loggedMinutes)
                                  : '${review.longestStreak}',
                              stats.loggedMinutes > 0
                                  ? 'reading time'
                                  : 'day streak',
                            ),
                          ],
                        ),
                        if (stats.finishedCount == 0) ...[
                          const SizedBox(height: 16),
                          Text(
                            'No finished books in ${widget.year} yet.',
                            style: onCard,
                          ),
                        ],
                        if (review.topRated.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Top rated',
                            style: onCard?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          for (final book in review.topRated)
                            Text('• ${book.title}', style: onCard),
                        ],
                        const SizedBox(height: 16),
                        if (author != null)
                          Text(
                            'Most read author: ${author.key} (${author.value})',
                            style: onCard,
                          ),
                        if (tag != null)
                          Text(
                            'Favorite tag: ${tag.key} (${tag.value})',
                            style: onCard,
                          ),
                        if (month != null)
                          Text(
                            'Busiest month: ${_monthNames[month - 1]} '
                            '(${stats.byMonth[month - 1]})',
                            style: onCard,
                          ),
                        if (average != null)
                          Text(
                            'Average rating: ${average.toStringAsFixed(1)}',
                            style: onCard,
                          ),
                        if (review.longestStreak > 1)
                          Text(
                            'Longest streak: ${review.longestStreak} days',
                            style: onCard,
                          ),
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
            ],
          );
        },
      ),
    );
  }
}
