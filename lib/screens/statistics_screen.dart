import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/statistics.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'year_review_screen.dart';

const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// Reading statistics, for all time or for one year, with a yearly goal.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int? _year;

  Future<void> _editGoal(int year, int? current) async {
    final controller = TextEditingController(text: current?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$year reading goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Books to read',
            helperText: 'Leave empty to remove the goal',
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
    if (saved != true) return;
    widget.settings.setGoal(year, int.tryParse(controller.text.trim()));
  }

  Future<void> _editPagesGoal(int year, int? current) async {
    final controller = TextEditingController(text: current?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$year pages goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Pages to read',
            helperText: 'Leave empty to remove the goal',
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
    final text = controller.text;
    controller.dispose();
    if (saved != true) return;
    widget.settings.setPagesGoal(year, int.tryParse(text.trim()));
  }

  Widget _pagesGoalCard(int year, BookStats stats) {
    final goal = widget.settings.pagesGoalFor(year);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$year pages goal', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (goal == null)
              const Text('No pages goal set for this year.')
            else
              _challengeRow(year, goal, stats.pagesRead, unit: 'pages'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _editPagesGoal(year, goal),
                child: Text(goal == null ? 'Set a goal' : 'Change goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTagGoal(int year) async {
    final tags = widget.repository.allTags;
    if (tags.isEmpty) return;
    var tag = tags.first;
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('$year tag goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: tag,
                decoration: const InputDecoration(labelText: 'Tag'),
                items: [
                  for (final t in tags)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (value) =>
                    setDialogState(() => tag = value ?? tag),
              ),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Books to read'),
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
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (saved != true) return;
    widget.settings.setTagGoal(year, tag, int.tryParse(text.trim()));
  }

  Widget _tagGoalsCard(int year, List<Book> books) {
    final goals = widget.settings.tagGoalsFor(year);
    final names = goals.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final hasTags = widget.repository.allTags.isNotEmpty;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$year tag goals', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (names.isEmpty)
              Text(
                hasTags
                    ? 'No tag goals yet, for example 10 books tagged sci-fi.'
                    : 'Add tags to your books to set goals for them.',
              ),
            for (final name in names)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name: ${finishedWithTag(books, name, year)} '
                            'of ${goals[name]}',
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (finishedWithTag(books, name, year) /
                                    (goals[name] ?? 1))
                                .clamp(0.0, 1.0)
                                .toDouble(),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove goal',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          widget.settings.setTagGoal(year, name, null),
                    ),
                  ],
                ),
              ),
            if (hasTags)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _addTagGoal(year),
                  child: const Text('Add a tag goal'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMonthlyGoal(int? current) async {
    final controller = TextEditingController(text: current?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Monthly reading goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Books to finish every month',
            helperText: 'Leave empty to remove the goal',
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
    final goal = int.tryParse(controller.text.trim());
    controller.dispose();
    if (saved != true) return;
    widget.settings.setMonthlyGoal(goal);
  }

  Widget _monthlyGoalCard(int year, BookStats stats) {
    final goal = widget.settings.monthlyGoal;
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final months = year == now.year ? now.month : year < now.year ? 12 : 0;
    var met = 0;
    if (goal != null) {
      for (var m = 0; m < months; m++) {
        if (stats.byMonth[m] >= goal) met++;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly goal', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (goal == null)
              const Text('No monthly goal set.')
            else ...[
              Text('Goal: $goal books a month'),
              Text('Reached in $met of $months months of $year'),
              if (year == now.year) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (stats.byMonth[now.month - 1] / goal)
                      .clamp(0.0, 1.0)
                      .toDouble(),
                ),
                const SizedBox(height: 4),
                Text('This month: ${stats.byMonth[now.month - 1]} of $goal'),
              ],
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _editMonthlyGoal(goal),
                child: Text(goal == null ? 'Set a goal' : 'Change goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _countSection(
    String title,
    List<MapEntry<String, int>> entries,
  ) {
    return [
      const SizedBox(height: 24),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(entry.key)),
              Text('${entry.value}'),
            ],
          ),
        ),
    ];
  }

  Widget _challengeRow(int year, int goal, int finished, {String unit = ''}) {
    final status = challengeStatus(
      finished: finished,
      goal: goal,
      year: year,
    );
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: status.progress,
                  strokeWidth: 8,
                ),
              ),
              Text(
                unit.isEmpty
                    ? '${status.finished}/${status.goal}'
                    : '${(status.progress * 100).round()}%',
                style: textTheme.titleMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            unit.isEmpty
                ? status.describe()
                : '${status.finished} of ${status.goal} $unit\n'
                    '${status.describe(unit: unit)}',
            style: textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }

  Widget _goalCard(int year, BookStats stats) {
    final goal = widget.settings.goalFor(year);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$year reading goal', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (goal == null)
              const Text('No goal set for this year.')
            else
              _challengeRow(year, goal, stats.finishedCount),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _editGoal(year, goal),
                child: Text(goal == null ? 'Set a goal' : 'Change goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.settings]),
        builder: (context, _) {
          final books = widget.repository.books;
          if (books.isEmpty) {
            return const Center(child: Text('Add some books to see statistics.'));
          }
          final overall = computeStats(books);
          final selected = _year;
          final year =
              selected != null && overall.byYear.containsKey(selected)
                  ? selected
                  : null;
          final stats = year == null ? overall : computeStats(books, year: year);
          final average = stats.averageRating;
          final longest = stats.longest;
          final textTheme = Theme.of(context).textTheme;
          final streak = currentStreak(books);
          final pagesToday = pagesLoggedOn(books, DateTime.now());
          final paces = [
            for (final book in books)
              if (readingPace(book) case final pace?) (book, pace),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (overall.byYear.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All time'),
                      selected: year == null,
                      onSelected: (_) => setState(() => _year = null),
                    ),
                    for (final y in overall.yearsNewestFirst)
                      ChoiceChip(
                        label: Text('$y'),
                        selected: year == y,
                        onSelected: (_) => setState(() => _year = y),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatTile(
                    label: 'Books finished',
                    value: stats.finishedCount.toString(),
                  ),
                  _StatTile(
                    label: 'Pages read',
                    value: stats.pagesRead.toString(),
                  ),
                  _StatTile(
                    label: 'Average rating',
                    value: average == null ? '–' : average.toStringAsFixed(1),
                  ),
                  _StatTile(
                    label: 'Average pages',
                    value: stats.averagePages?.toString() ?? '–',
                  ),
                  if (stats.loggedPages > 0)
                    _StatTile(
                      label: 'Pages in reading log',
                      value: stats.loggedPages.toString(),
                    ),
                  if (stats.loggedMinutes > 0)
                    _StatTile(
                      label: 'Time read',
                      value: formatMinutes(stats.loggedMinutes),
                    ),
                  if (streak > 0)
                    _StatTile(
                      label: 'Reading streak',
                      value: '$streak ${streak == 1 ? 'day' : 'days'}',
                    ),
                  if (pagesToday > 0)
                    _StatTile(
                      label: 'Pages today',
                      value: pagesToday.toString(),
                    ),
                  if (longest != null)
                    _StatTile(
                      label: 'Longest book',
                      value: '${longest.pages} pages',
                      detail: longest.title,
                    ),
                ],
              ),
              if (year != null) ...[
                const SizedBox(height: 24),
                _goalCard(year, stats),
                const SizedBox(height: 12),
                _pagesGoalCard(year, stats),
                const SizedBox(height: 12),
                _tagGoalsCard(year, books),
                const SizedBox(height: 12),
                _monthlyGoalCard(year, stats),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: Text('$year in review'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => YearReviewScreen(
                        repository: widget.repository,
                        fileIo: widget.fileIo,
                        year: year,
                      ),
                    ),
                  ),
                ),
              ],
              if (year == null) ...[
                const SizedBox(height: 24),
                Text('By shelf', style: textTheme.titleMedium),
                for (final shelf in Shelf.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(shelf.label)),
                        Text('${stats.shelfCounts[shelf] ?? 0}'),
                      ],
                    ),
                  ),
              ],
              if (stats.formatCounts.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('By format', style: textTheme.titleMedium),
                for (final format in BookFormat.values)
                  if (stats.formatCounts.containsKey(format))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(format.label)),
                          Text('${stats.formatCounts[format]}'),
                        ],
                      ),
                    ),
              ],
              if (stats.ratingCounts.values.any((count) => count > 0)) ...[
                const SizedBox(height: 24),
                Text('Ratings', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                _BarChart(
                  labels: const ['1★', '2★', '3★', '4★', '5★'],
                  values: [
                    for (var star = 1; star <= 5; star++)
                      stats.ratingCounts[star] ?? 0,
                  ],
                ),
              ],
              if (stats.topAuthors.isNotEmpty)
                ..._countSection('Most read authors', stats.topAuthors),
              if (stats.topTags.isNotEmpty)
                ..._countSection('Most used tags', stats.topTags),
              if (paces.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Reading pace', style: textTheme.titleMedium),
                for (final (book, pace) in paces)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title),
                        Text(pace.describe(), style: textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              if (year == null && overall.byYear.isNotEmpty) ...[
                Text('Books finished per year', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                _BarChart(
                  labels: [for (final y in overall.byYear.keys) '$y'],
                  values: overall.byYear.values.toList(),
                ),
                if (overall.pagesByYear.values.any((pages) => pages > 0)) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Pages finished per year',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _BarChart(
                    labels: [for (final y in overall.pagesByYear.keys) '$y'],
                    values: overall.pagesByYear.values.toList(),
                  ),
                ],
              ] else if (year != null) ...[
                Text(
                  'Books finished per month in $year',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _BarChart(labels: _monthLetters, values: stats.byMonth),
                if (stats.pagesRead > 0) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Pages finished per month in $year',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _BarChart(labels: _monthLetters, values: stats.pagesByMonth),
                ],
                if (stats.loggedPages > 0) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Pages logged per month in $year',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _BarChart(labels: _monthLetters, values: stats.loggedByMonth),
                ],
              ],
              if (overall.finishedWithoutDate > 0) ...[
                const SizedBox(height: 24),
                Text(
                  '${overall.finishedWithoutDate} finished '
                  '${overall.finishedWithoutDate == 1 ? 'book has' : 'books have'}'
                  ' no finish date, so they are left out of the yearly and '
                  'monthly charts. Open a book to set its finish date.',
                  style: textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final detail = this.detail;
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, style: textTheme.bodySmall),
              if (detail != null)
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1200 becomes "1.2k" so big numbers fit above a narrow bar.
String _compact(int value) {
  if (value < 1000) return value.toString();
  final thousands = value / 1000;
  return '${thousands.toStringAsFixed(thousands < 10 ? 1 : 0)}k';
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.labels, required this.values});

  final List<String> labels;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, (max, value) => value > max ? value : max);
    final color = Theme.of(context).colorScheme.primary;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      values[i] == 0 ? '' : _compact(values[i]),
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: maxValue == 0 ? 0 : 110 * values[i] / maxValue,
                      child: ColoredBox(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
