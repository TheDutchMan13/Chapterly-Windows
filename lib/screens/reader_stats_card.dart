import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../ebook/ebook_library.dart';
import '../ebook/ebook_reading.dart';
import '../ebook/reader_stats.dart';

// The same file is in the Android and the Windows app.

/// Time spent in Chapterly's reader on this device: in all, this week, the
/// longest run of days, reading speed and the books read most. Hidden until
/// there is some.
class ReaderStatsCard extends StatelessWidget {
  const ReaderStatsCard({super.key, required this.repository, this.library});

  final BookRepository repository;

  /// Defaults to the device's reader library.
  final EbookLibrary? library;

  @override
  Widget build(BuildContext context) {
    final source = library ?? EbookReading.library;
    if (source == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final summary = readerSummary(
          source.links,
          bookPages: (id) => repository.byId(id)?.pages,
        );
        if (summary.isEmpty) return const SizedBox.shrink();
        final textTheme = Theme.of(context).textTheme;
        final pace = summary.pagesPerHour;
        Widget line(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Text(value, style: textTheme.titleSmall),
                ],
              ),
            );
        return Card(
          margin: const EdgeInsets.only(top: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chrome_reader_mode_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'In the reader on this device',
                        style: textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                line('Time reading', formatMinutes(summary.totalMinutes)),
                line('Last 7 days', formatMinutes(summary.lastWeekMinutes)),
                line(
                  'Days with reading',
                  '${summary.daysRead}',
                ),
                if (summary.longestStreak > 1)
                  line(
                    'Most days in a row',
                    '${summary.longestStreak} days',
                  ),
                if (pace != null) line('Speed', pagesPerHourText(pace)),
                if (summary.topBooks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Read most', style: textTheme.labelLarge),
                  for (final (id, minutes) in summary.topBooks)
                    line(
                      repository.byId(id)?.title ?? 'A removed book',
                      formatMinutes(minutes),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Reading time also goes into each book\'s reading log, so '
                  'it counts in Time read above.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
