import 'package:flutter/material.dart';

import '../models/shelf.dart';

// The same file is in the Android app.

/// The colours of the Statistics page. Bright enough to read on a dark page,
/// and every colour is also written out as a label or a number.
const statsGreen = Color(0xFF4FD1A5);
const statsBlue = Color(0xFF6AB7FF);
const statsAmber = Color(0xFFF5B94A);
const statsViolet = Color(0xFFB794F6);
const statsCoral = Color(0xFFF0746A);
const statsTeal = Color(0xFF5AD1C0);
const statsPink = Color(0xFFF3A3C7);
const statsLime = Color(0xFF9BE28A);

/// The colour of a shelf, the same everywhere on the Statistics page.
Color shelfColor(Shelf shelf) => switch (shelf) {
      Shelf.finished => statsGreen,
      Shelf.inProgress => statsBlue,
      Shelf.forLater => statsAmber,
      Shelf.unfinished => statsCoral,
      Shelf.wishlist => statsViolet,
    };

/// A number with a label, tinted in its own colour and with an icon.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = this.detail;
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.16),
          theme.colorScheme.surface,
        ),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: Colors.black87),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: theme.textTheme.bodyMedium),
          if (detail != null)
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

/// A rounded block that holds one part of the Statistics page.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// One row: a colour, a label, a bar as long as [fraction], and a number.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                // A small count still shows a sliver of colour.
                value: value == 0 ? 0 : fraction.clamp(0.012, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerLowest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many books are on each shelf: one bar with a piece for every shelf,
/// and a row for each shelf below it.
class ShelfBreakdown extends StatelessWidget {
  const ShelfBreakdown({super.key, required this.counts});

  final Map<Shelf, int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = counts.values.fold<int>(0, (sum, n) => sum + n);
    final biggest = counts.values.fold<int>(0, (m, n) => n > m ? n : m);
    return StatsCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Text('By shelf', style: theme.textTheme.titleMedium),
            ),
            Text('$total books', style: theme.textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 14,
            child: total == 0
                ? ColoredBox(color: theme.colorScheme.surfaceContainerLowest)
                : Row(
                    children: [
                      for (final shelf in Shelf.values)
                        if ((counts[shelf] ?? 0) > 0)
                          Expanded(
                            flex: counts[shelf]!,
                            child: ColoredBox(color: shelfColor(shelf)),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        for (final shelf in Shelf.values)
          _BarRow(
            label: shelf.label,
            value: counts[shelf] ?? 0,
            fraction: biggest == 0 ? 0 : (counts[shelf] ?? 0) / biggest,
            color: shelfColor(shelf),
          ),
      ],
    );
  }
}

/// A list of counts as coloured bars, longest first reading as the biggest.
class BarRows extends StatelessWidget {
  const BarRows({super.key, required this.title, required this.rows});

  final String title;
  final List<(String, int, Color)> rows;

  @override
  Widget build(BuildContext context) {
    final biggest = rows.fold<int>(0, (m, row) => row.$2 > m ? row.$2 : m);
    return StatsCard(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (label, value, color) in rows)
          _BarRow(
            label: label,
            value: value,
            fraction: biggest == 0 ? 0 : value / biggest,
            color: color,
          ),
      ],
    );
  }
}
