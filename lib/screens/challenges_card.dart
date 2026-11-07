// The same file is in both apps (lib/screens/challenges_card.dart).

import 'dart:math';

import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/challenges.dart';
import '../models/book.dart';

/// Your reading challenges, with a progress bar each, and a button to add
/// one: "12 books by March", "5 different authors this summer".
class ChallengesCard extends StatelessWidget {
  const ChallengesCard({
    super.key,
    required this.settings,
    required this.books,
    required this.tags,
  });

  final AppSettings settings;
  final List<Book> books;

  /// Tags in the library, offered for a tag challenge.
  final List<String> tags;

  Future<void> _edit(BuildContext context, [ReadingChallenge? old]) async {
    final saved = await showDialog<ReadingChallenge>(
      context: context,
      builder: (_) => ChallengeDialog(challenge: old, tags: tags),
    );
    if (saved != null) settings.saveChallenge(saved);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final progress = [
          for (final challenge in settings.challenges)
            challengeProgress(challenge, books),
        ]..sort((a, b) {
            // Running ones first, then ones still to come, then ended ones.
            int rank(ChallengeProgress p) => p.ended ? 2 : (p.notStarted ? 1 : 0);
            final byRank = rank(a).compareTo(rank(b));
            if (byRank != 0) return byRank;
            return a.challenge.end.compareTo(b.challenge.end);
          });
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Challenges', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                if (progress.isEmpty)
                  const Text(
                    'Set your own challenge between any two dates, for '
                    'example 12 books by March or 5 new authors this summer.',
                  ),
                for (final item in progress)
                  _ChallengeRow(
                    progress: item,
                    onEdit: () => _edit(context, item.challenge),
                    onRemove: () =>
                        settings.removeChallenge(item.challenge.id),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Add challenge'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.progress,
    required this.onEdit,
    required this.onRemove,
  });

  final ChallengeProgress progress;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final challenge = progress.challenge;
    final kind = challenge.kind == ChallengeKind.tag
        ? 'Books tagged ${challenge.tag}'
        : challenge.kind.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            progress.reached ? Icons.emoji_events : Icons.flag_outlined,
            color: progress.reached ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(challenge.name, style: textTheme.titleSmall),
                Text(
                  '$kind · ${challengeDates(challenge)}',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Text(progress.describe(), style: textTheme.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Challenge options',
            onSelected: (choice) =>
                choice == 'edit' ? onEdit() : onRemove(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Makes or changes a challenge. Returns it, or null when cancelled.
class ChallengeDialog extends StatefulWidget {
  const ChallengeDialog({super.key, this.challenge, required this.tags});

  final ReadingChallenge? challenge;
  final List<String> tags;

  @override
  State<ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<ChallengeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late ChallengeKind _kind;
  late DateTime _start;
  late DateTime _end;
  String? _tag;

  @override
  void initState() {
    super.initState();
    final old = widget.challenge;
    final today = DateTime.now();
    _name = TextEditingController(text: old?.name ?? '');
    _target = TextEditingController(text: old == null ? '' : '${old.target}');
    _kind = old?.kind ?? ChallengeKind.books;
    _start = old?.start ?? DateTime(today.year, today.month, today.day);
    _end = old?.end ?? DateTime(today.year, today.month + 3, today.day);
    _tag = old?.tag ?? widget.tags.firstOrNull;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  int? get _targetValue {
    final value = int.tryParse(_target.text.trim());
    return value != null && value > 0 ? value : null;
  }

  bool get _valid =>
      _targetValue != null &&
      !_end.isBefore(_start) &&
      (_kind != ChallengeKind.tag || (_tag?.isNotEmpty ?? false));

  String _defaultName() {
    final target = _targetValue ?? 0;
    final what = _kind == ChallengeKind.tag
        ? '${_kind.unit(target)} tagged $_tag'
        : _kind.unit(target);
    return '$target $what';
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  void _save() {
    final name = _name.text.trim();
    Navigator.of(context).pop(
      ReadingChallenge(
        id: widget.challenge?.id ?? _newId(),
        name: name.isEmpty ? _defaultName() : name,
        kind: _kind,
        target: _targetValue!,
        start: _start,
        end: _end,
        tag: _kind == ChallengeKind.tag ? _tag : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.challenge == null ? 'New challenge' : 'Edit challenge'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ChallengeKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Count'),
                items: [
                  for (final kind in ChallengeKind.values)
                    if (kind != ChallengeKind.tag || widget.tags.isNotEmpty)
                      DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (kind) => setState(() => _kind = kind ?? _kind),
              ),
              if (_kind == ChallengeKind.tag) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tag,
                  decoration: const InputDecoration(labelText: 'Tag'),
                  items: [
                    for (final tag in widget.tags)
                      DropdownMenuItem(value: tag, child: Text(tag)),
                  ],
                  onChanged: (tag) => setState(() => _tag = tag),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Goal',
                  suffixText: _kind.unit(_targetValue ?? 2),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('From ${localizations.formatMediumDate(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('To ${localizations.formatMediumDate(_end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: _defaultName(),
                ),
              ),
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
          onPressed: _valid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _newId() {
  final random = Random();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return [for (var i = 0; i < 10; i++) chars[random.nextInt(chars.length)]]
      .join();
}
