import 'package:flutter/material.dart';

/// How many tags are shown as chips before "All tags".
const visibleTagCount = 12;

/// Where a tag stands in a filter.
enum TagChoice { none, included, excluded }

/// The tags to show as chips: every tag in use in the filter first, then
/// the most used (ties alphabetically), [limit] in all (more when the
/// filter uses more). A library with hundreds of tags would otherwise be
/// hundreds of chips, which are slow to build and push the books off the
/// screen.
List<String> chipTags(
  Map<String, int> counts,
  Set<String> inUse, {
  int limit = visibleTagCount,
}) {
  final used = [
    for (final tag in inUse)
      if (counts.containsKey(tag)) tag,
  ]..sort(_byName);
  final rest = [
    for (final tag in counts.keys)
      if (!inUse.contains(tag)) tag,
  ]..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : _byName(a, b);
    });
  return [...used, ...rest.take((limit - used.length).clamp(0, limit))];
}

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// A chip that opens the list of every tag. Say how many there are.
ActionChip allTagsChip({required int total, required VoidCallback onPressed}) =>
    ActionChip(
      avatar: const Icon(Icons.sell_outlined, size: 18),
      label: Text('All tags ($total)'),
      onPressed: onPressed,
    );

/// Every tag, with a search box and how many books have each. Tapping a tag
/// calls [onTap]; [choiceOf] says how it shows afterwards.
Future<void> showTagPicker(
  BuildContext context, {
  required Map<String, int> counts,
  required TagChoice Function(String tag) choiceOf,
  required void Function(String tag) onTap,
  bool canExclude = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TagPicker(
      counts: counts,
      choiceOf: choiceOf,
      onTap: onTap,
      canExclude: canExclude,
    ),
  );
}

class _TagPicker extends StatefulWidget {
  const _TagPicker({
    required this.counts,
    required this.choiceOf,
    required this.onTap,
    required this.canExclude,
  });

  final Map<String, int> counts;
  final TagChoice Function(String) choiceOf;
  final void Function(String) onTap;
  final bool canExclude;

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  final _search = TextEditingController();
  late final List<String> _all = widget.counts.keys.toList()..sort(_byName);
  var _byUse = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _shown {
    final words = _search.text.trim().toLowerCase();
    final list = [
      for (final tag in _all)
        if (words.isEmpty || tag.toLowerCase().contains(words)) tag,
    ];
    if (_byUse) {
      list.sort((a, b) {
        final byCount = widget.counts[b]!.compareTo(widget.counts[a]!);
        return byCount != 0 ? byCount : _byName(a, b);
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return AlertDialog(
      title: Text('All tags (${widget.counts.length})'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Find a tag',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Most used')),
                    ButtonSegment(value: false, label: Text('A to Z')),
                  ],
                  selected: {_byUse},
                  onSelectionChanged: (choice) =>
                      setState(() => _byUse = choice.first),
                ),
              ),
            ),
            if (widget.canExclude)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Tap once to show these books, again to hide them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No tag like that.'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final tag = shown[i];
                        final choice = widget.choiceOf(tag);
                        return ListTile(
                          dense: true,
                          title: Text(
                            tag,
                            style: choice == TagChoice.excluded
                                ? const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                  )
                                : null,
                          ),
                          subtitle: Text('${widget.counts[tag]} books'),
                          trailing: switch (choice) {
                            TagChoice.included => Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            TagChoice.excluded => const Icon(Icons.block),
                            TagChoice.none => null,
                          },
                          onTap: () {
                            widget.onTap(tag);
                            setState(() {});
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
