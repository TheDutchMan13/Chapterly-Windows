import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../ebook/ebook_library.dart';
import '../ebook/reader_style.dart';
import '../ebook/reader_tools.dart';

// The same file is in the Android and the Windows app: pieces of the
// reader that look and work the same on both.

/// Asks for words to search for. Null when cancelled or empty.
Future<String?> askForSearchWords(BuildContext context) async {
  final controller = TextEditingController();
  final query = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Search in the book'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(labelText: 'Words to find'),
        onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Search'),
        ),
      ],
    ),
  );
  controller.dispose();
  final words = query?.trim() ?? '';
  return words.isEmpty ? null : words;
}

/// A round colour swatch for choosing a highlight colour.
class HighlightDot extends StatelessWidget {
  const HighlightDot({
    super.key,
    required this.colour,
    required this.onTap,
    this.selected = false,
    this.tooltip,
  });

  final HighlightColour colour;
  final VoidCallback onTap;
  final bool selected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? colour.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip ?? colour.label,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: highlightSwatch(colour),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outline,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the highlight editor did.
enum HighlightEdit { changed, removed }

/// Changes a highlight's colour and note, or removes it. The quote saved on
/// the book stays either way.
Future<HighlightEdit?> showHighlightEditor(
  BuildContext context, {
  required EbookLibrary library,
  required String bookId,
  required EbookHighlight highlight,
}) {
  return showDialog<HighlightEdit>(
    context: context,
    builder: (dialogContext) => _HighlightEditor(
      library: library,
      bookId: bookId,
      highlight: highlight,
    ),
  );
}

class _HighlightEditor extends StatefulWidget {
  const _HighlightEditor({
    required this.library,
    required this.bookId,
    required this.highlight,
  });

  final EbookLibrary library;
  final String bookId;
  final EbookHighlight highlight;

  @override
  State<_HighlightEditor> createState() => _HighlightEditorState();
}

class _HighlightEditorState extends State<_HighlightEditor> {
  late HighlightColour _colour = widget.highlight.colour;
  late final _note = TextEditingController(text: widget.highlight.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await widget.library.updateHighlight(
      widget.bookId,
      widget.highlight.locator,
      colour: _colour,
      note: () => _note.text,
    );
    navigator.pop(HighlightEdit.changed);
  }

  Future<void> _remove() async {
    final navigator = Navigator.of(context);
    await widget.library.removeHighlight(
      widget.bookId,
      widget.highlight.locator,
    );
    navigator.pop(HighlightEdit.removed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Highlight'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.highlight.text,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              Wrap(
                children: [
                  for (final colour in HighlightColour.values)
                    HighlightDot(
                      colour: colour,
                      selected: colour == _colour,
                      onTap: () => setState(() => _colour = colour),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Your thoughts on this passage',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Removing the highlight leaves the quote on the book page.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _remove, child: const Text('Remove')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// A highlight in the list of highlights: its colour, words and note.
class HighlightTile extends StatelessWidget {
  const HighlightTile({
    super.key,
    required this.highlight,
    required this.onGo,
    required this.onEdit,
  });

  final EbookHighlight highlight;
  final VoidCallback onGo;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final note = highlight.note;
    return ListTile(
      leading: Container(
        width: 14,
        height: 40,
        decoration: BoxDecoration(
          color: highlightSwatch(highlight.colour),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Text(
        highlight.text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontStyle: FontStyle.italic),
      ),
      subtitle: note == null
          ? null
          : Text(note, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: 'Colour, note or remove',
        icon: const Icon(Icons.edit_note),
        onPressed: onEdit,
      ),
      onTap: onGo,
    );
  }
}

/// Shows a footnote's words over the page.
Future<void> showFootnote(
  BuildContext context, {
  required String text,
  String? label,
  VoidCallback? onGoToNote,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(label == null || label.isEmpty ? 'Note' : 'Note $label'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: SelectableText(text.isEmpty ? 'This note is empty.' : text),
        ),
      ),
      actions: [
        if (onGoToNote != null)
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onGoToNote();
            },
            child: const Text('Go to the note'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// The controls while the book is read aloud: stop and speed.
class ReadAloudBar extends StatelessWidget {
  const ReadAloudBar({
    super.key,
    required this.colours,
    required this.rate,
    required this.onStop,
    required this.onRate,
  });

  final ReaderColors colours;
  final double rate;
  final VoidCallback onStop;
  final ValueChanged<double> onRate;

  static const rates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colours.bar,
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.record_voice_over, color: colours.foreground, size: 20),
            const SizedBox(width: 8),
            Text('Reading aloud', style: TextStyle(color: colours.foreground)),
            PopupMenuButton<double>(
              tooltip: 'Speed',
              initialValue: rate,
              onSelected: onRate,
              itemBuilder: (_) => [
                for (final r in rates)
                  PopupMenuItem(value: r, child: Text(speedText(r))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Text(
                  speedText(rate),
                  style: TextStyle(
                    color: colours.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Stop reading aloud',
              color: colours.foreground,
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

/// "1.25×".
String speedText(double rate) {
  final text = rate == rate.roundToDouble()
      ? rate.toStringAsFixed(0)
      : rate.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return '$text×';
}

/// Moving through the places a PDF search found.
class PdfSearchBar extends StatelessWidget {
  const PdfSearchBar({
    super.key,
    required this.searcher,
    required this.words,
    required this.colours,
    required this.onClose,
  });

  final PdfTextSearcher searcher;
  final String words;
  final ReaderColors colours;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colours.bar,
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      child: ListenableBuilder(
        listenable: searcher,
        builder: (context, _) {
          final count = searcher.matches.length;
          final current = searcher.currentIndex;
          final String status;
          if (count == 0) {
            status = searcher.isSearching ? 'Searching...' : 'Not found';
          } else {
            status = '${current == null ? '–' : current + 1} of $count'
                '${searcher.isSearching ? '+' : ''}';
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '"$words"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colours.foreground),
                  ),
                ),
                const SizedBox(width: 8),
                Text(status, style: TextStyle(color: colours.muted)),
                IconButton(
                  tooltip: 'Previous',
                  color: colours.foreground,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: count == 0 ? null : searcher.goToPrevMatch,
                ),
                IconButton(
                  tooltip: 'Next',
                  color: colours.foreground,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: count == 0 ? null : searcher.goToNextMatch,
                ),
                IconButton(
                  tooltip: 'Close the search',
                  color: colours.foreground,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A PDF's own table of contents (its outline), with sub-entries indented.
class PdfOutlineList extends StatelessWidget {
  const PdfOutlineList({
    super.key,
    required this.outline,
    required this.onPage,
    this.controller,
    this.currentPage,
  });

  final List<PdfOutlineNode> outline;
  final ValueChanged<int> onPage;
  final ScrollController? controller;
  final int? currentPage;

  static List<(PdfOutlineNode, int)> flatten(
    List<PdfOutlineNode> nodes, [
    int depth = 0,
  ]) =>
      [
        for (final node in nodes) ...[
          (node, depth),
          ...flatten(node.children, depth + 1),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final entries = flatten(outline);
    return ListView(
      controller: controller,
      children: [
        for (final (node, depth) in entries)
          ListTile(
            contentPadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 16),
            title: Text(node.title.trim().isEmpty ? 'Untitled' : node.title.trim()),
            trailing: node.dest == null ? null : Text('${node.dest!.pageNumber}'),
            enabled: node.dest != null,
            onTap: node.dest == null ? null : () => onPage(node.dest!.pageNumber),
          ),
      ],
    );
  }
}

/// The "only for this book" switch at the top of the text settings.
class OwnLookTile extends StatelessWidget {
  const OwnLookTile({
    super.key,
    required this.library,
    required this.bookId,
  });

  final EbookLibrary library;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final own = library.hasOwnLook(bookId);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Only for this book'),
      subtitle: Text(
        own
            ? 'Changes here are kept for this book. Turn off to use your '
                'usual settings again.'
            : 'Changes here apply to every book.',
      ),
      value: own,
      onChanged: (value) => library.setOwnLook(bookId, own: value),
    );
  }
}

/// How fast the book is read aloud.
class SpeechRateSlider extends StatelessWidget {
  const SpeechRateSlider({
    super.key,
    required this.rate,
    required this.onChanged,
  });

  final double rate;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.slow_motion_video, size: 20),
        Expanded(
          child: Slider(
            value: rate.clamp(ReaderPrefs.minSpeechRate, ReaderPrefs.maxSpeechRate),
            min: ReaderPrefs.minSpeechRate,
            max: ReaderPrefs.maxSpeechRate,
            divisions: 6,
            label: speedText(rate),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 48, child: Text(speedText(rate))),
      ],
    );
  }
}

/// Whether [text] can be looked up, for showing the Look up button.
bool showLookUp(String? text) => text != null && canLookUp(text);
