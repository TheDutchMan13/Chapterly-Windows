import 'package:flutter/material.dart';

import '../audio/audio_bookmarks.dart';
import '../audio/listen_controller.dart';
import '../audio/listening.dart';
import '../data/book_repository.dart';
import '../models/audio_progress.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'listen_card.dart';
import 'mini_player.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

/// 1 becomes "1×", 1.25 becomes "1.25×".
String _speedLabel(double speed) {
  var text = speed.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return '$text×';
}

/// Opens the full player.
void openPlayer(BuildContext context) {
  final controller = Listening.controller;
  if (controller == null || !controller.active) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(controller: controller),
    ),
  );
}

/// Puts the "now playing" bar under every page while a book's audio is
/// open, and asks to move a book to Finished when it has been heard to the
/// end. Wraps the whole app.
class NowPlayingFrame extends StatefulWidget {
  const NowPlayingFrame({
    super.key,
    required this.repository,
    required this.child,
  });

  final BookRepository repository;
  final Widget child;

  @override
  State<NowPlayingFrame> createState() => _NowPlayingFrameState();
}

class _NowPlayingFrameState extends State<NowPlayingFrame> {
  @override
  void initState() {
    super.initState();
    Listening.controller?.onFinished = _finished;
  }

  Future<void> _finished(Book book) async {
    if (book.shelf == Shelf.finished) return;
    final context = Listening.navigatorKey.currentContext;
    if (context == null) return;
    final move = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finished listening?'),
        content: Text('You reached the end of "${book.title}". Move it to '
            'Finished?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Move to Finished'),
          ),
        ],
      ),
    );
    if (move == true) await widget.repository.moveTo(book.id, Shelf.finished);
  }

  @override
  Widget build(BuildContext context) {
    final controller = Listening.controller;
    if (controller == null) return widget.child;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = controller.active;
        final media = MediaQuery.of(context);
        // The tree stays the same whether the bar shows or not, so the pages
        // keep their state.
        return Column(
          children: [
            Expanded(
              child: MediaQuery(
                data: active ? media.removePadding(removeBottom: true) : media,
                child: widget.child,
              ),
            ),
            if (active) _NowPlayingBar(controller: controller),
          ],
        );
      },
    );
  }
}

/// The small player under the pages. It sits outside the pages, so it has
/// no tooltips (they need a page around them).
class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({required this.controller});

  final ListenController controller;

  @override
  Widget build(BuildContext context) {
    final book = controller.book;
    if (book == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chapters = controller.chapters;
    final index = controller.chapterIndex;
    final span = controller.chapterSpan;
    double? value;
    if (span != null) {
      final total = (span.end - span.start).inMilliseconds;
      final done = (controller.trackPosition - span.start).inMilliseconds;
      if (total > 0) value = (done / total).clamp(0.0, 1.0);
    }
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () {
            final navigator = Listening.navigatorKey.currentState;
            navigator?.push(
              MaterialPageRoute<void>(
                builder: (_) => PlayerScreen(controller: controller),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value ?? 0, minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    BookCover(coverUrl: book.coverUrl, width: 32, height: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall,
                          ),
                          Text(
                            index != null
                                ? chapters[index].title
                                : describeAudioProgress(
                                    controller.progress,
                                    controller.link,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.replay_30,
                        semanticLabel: 'Back 30 seconds',
                      ),
                      onPressed: () =>
                          controller.skip(const Duration(seconds: -30)),
                    ),
                    IconButton(
                      icon: Icon(
                        controller.playing ? Icons.pause : Icons.play_arrow,
                        semanticLabel: controller.playing ? 'Pause' : 'Play',
                      ),
                      onPressed: controller.toggle,
                    ),
                    IconButton(
                      tooltip: 'Mini player',
                      icon: const Icon(Icons.picture_in_picture_alt_outlined),
                      onPressed: MiniPlayer.instance.enter,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        semanticLabel: 'Close the player',
                      ),
                      onPressed: controller.close,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full player: cover, chapter, position, speed, sleep timer and the
/// list of chapters.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.controller});

  final ListenController controller;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Where the slider is while it is being dragged.
  double? _dragging;

  ListenController get _c => widget.controller;

  Future<void> _showChapters() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => _ChapterList(
          chapters: [for (final c in _c.chapters) c.title],
          current: _c.chapterIndex,
          controller: scroll,
          onTap: (i) => Navigator.of(sheetContext).pop(i),
        ),
      ),
    );
    if (chosen != null) await _c.goToChapter(chosen);
  }

  // ---- Bookmarks (kept with the book, so they sync)

  String _placeLabel(AudioBookmark mark) {
    final clock = formatPlayerClock(Duration(milliseconds: mark.positionMs));
    final index = _c.link?.chapterAt(mark.track, mark.trackMs);
    final chapters = _c.chapters;
    if (index == null || index >= chapters.length) return clock;
    return '$clock · ${chapters[index].title}';
  }

  Future<void> _addBookmark() async {
    final store = AudioBookmarking.repository;
    final id = _c.bookId;
    final progress = _c.progress;
    if (store == null || id == null || progress == null) return;
    final track = _c.track;
    final trackMs = _c.trackPosition.inMilliseconds;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add a bookmark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'At ${formatPlayerClock(Duration(milliseconds: progress.positionMs))}',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await store.addBookmark(
      id,
      AudioBookmark(
        track: track,
        trackMs: trackMs,
        positionMs: progress.positionMs,
        addedAt: DateTime.now(),
        note: note.trim(),
      ),
    );
    messenger.showSnackBar(const SnackBar(content: Text('Bookmark added')));
  }

  Future<void> _editNote(String id, AudioBookmark mark) async {
    final store = AudioBookmarking.repository;
    if (store == null) return;
    final controller = TextEditingController(text: mark.note);
    final note = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Bookmark note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note != null) await store.setBookmarkNote(id, mark, note);
  }

  Future<void> _showBookmarks() async {
    final store = AudioBookmarking.repository;
    final id = _c.bookId;
    if (store == null || id == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final marks = store.bookmarksFor(id);
            if (marks.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No bookmarks yet. Use Bookmark to save the place '
                    'you are at, with a note if you like.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              controller: scroll,
              itemCount: marks.length,
              itemBuilder: (context, index) {
                final mark = marks[index];
                return ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(_placeLabel(mark)),
                  subtitle: mark.note.isEmpty ? null : Text(mark.note),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _c.seekTo(
                      mark.track,
                      Duration(milliseconds: mark.trackMs),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit note',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editNote(id, mark),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => store.removeBookmark(id, mark),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _sleepLabel() {
    if (_c.sleepAtChapterEnd) return 'End of chapter';
    final left = _c.sleepLeft;
    if (left == null) return 'Sleep timer';
    return '${formatPlayerClock(left)} left';
  }

  Widget _cover(Book book, double width) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 28,
            offset: Offset(0, 10),
            color: Color(0x40000000),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BookCover(
          coverUrl: book.coverUrl,
          width: width,
          height: width * 1.5,
        ),
      ),
    );
  }

  /// Title, chapter, the position slider, the buttons and speed and sleep.
  List<Widget> _controls(
    BuildContext context,
    Book book, {
    required bool showChapterButton,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final chapters = _c.chapters;
    final index = _c.chapterIndex;
    final span = _c.chapterSpan;
    final position = _c.trackPosition;
    final start = span?.start ?? Duration.zero;
    final end = span?.end ?? position;
    final total = (end - start).inMilliseconds.toDouble();
    final done = (position - start).inMilliseconds.toDouble();
    final double slider =
        total <= 0 ? 0 : (_dragging ?? done.clamp(0, total).toDouble());
    final progress = _c.progress;
    final length = progress?.lengthMs;
    final leftMs = length == null ? null : length - progress!.positionMs;
    final bookFraction = progress?.fraction;
    return [
      Text(
        book.title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.headlineSmall,
      ),
      if (book.author.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          book.author,
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (index != null) ...[
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Chapter ${index + 1} of ${chapters.length}',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          chapters[index].title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall,
        ),
      ],
      const SizedBox(height: 12),
      Slider(
        value: total <= 0 ? 0 : slider,
        max: total <= 0 ? 1 : total,
        onChanged:
            total <= 0 ? null : (value) => setState(() => _dragging = value),
        onChangeEnd: total <= 0
            ? null
            : (value) {
                setState(() => _dragging = null);
                _c.seekInTrack(start + Duration(milliseconds: value.round()));
              },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(
              formatPlayerClock(Duration(milliseconds: slider.round())),
              style: textTheme.bodySmall,
            ),
            const Spacer(),
            Text(
              '-${formatPlayerClock(
                Duration(milliseconds: (total - slider).round()),
              )}',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Previous chapter',
            iconSize: 32,
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: chapters.isEmpty ? null : _c.previousChapter,
          ),
          IconButton(
            tooltip: 'Back 30 seconds',
            iconSize: 36,
            icon: const Icon(Icons.replay_30_rounded),
            onPressed: () => _c.skip(const Duration(seconds: -30)),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: IconButton.filled(
              tooltip: _c.playing ? 'Pause' : 'Play',
              iconSize: 44,
              icon: Icon(
                _c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              onPressed: _c.toggle,
            ),
          ),
          IconButton(
            tooltip: 'Forward 30 seconds',
            iconSize: 36,
            icon: const Icon(Icons.forward_30_rounded),
            onPressed: () => _c.skip(const Duration(seconds: 30)),
          ),
          IconButton(
            tooltip: 'Next chapter',
            iconSize: 32,
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: chapters.isEmpty ? null : _c.nextChapter,
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (bookFraction != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: bookFraction, minHeight: 6),
        ),
        const SizedBox(height: 6),
      ],
      Text(
        [
          describeAudioProgress(progress, _c.link),
          if (leftMs != null && leftMs > 0)
            '${formatListenTime(leftMs ~/ _c.speed)} left in the book'
                '${_c.speed == 1 ? '' : ' at ${_speedLabel(_c.speed)}'}',
        ].join(' · '),
        textAlign: TextAlign.center,
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          PopupMenuButton<double>(
            tooltip: 'Speed',
            initialValue: _c.speed,
            onSelected: _c.setSpeed,
            itemBuilder: (_) => [
              for (final speed in _speeds)
                CheckedPopupMenuItem(
                  value: speed,
                  checked: speed == _c.speed,
                  child: Text(_speedLabel(speed)),
                ),
            ],
            child: _PlayerAction(
              icon: Icons.speed,
              label: _speedLabel(_c.speed),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Sleep timer',
            onSelected: (minutes) {
              if (minutes == -1) {
                _c.sleepAtEndOfChapter();
              } else {
                _c.setSleepTimer(
                  minutes == 0 ? null : Duration(minutes: minutes),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 0, child: Text('Off')),
              for (final minutes in [5, 10, 15, 30, 45, 60])
                PopupMenuItem(value: minutes, child: Text('$minutes minutes')),
              if (chapters.isNotEmpty)
                const PopupMenuItem(
                  value: -1,
                  child: Text('End of this chapter'),
                ),
            ],
            child: _PlayerAction(
              icon: _c.sleepLeft != null || _c.sleepAtChapterEnd
                  ? Icons.bedtime
                  : Icons.bedtime_outlined,
              label: _sleepLabel(),
              active: _c.sleepLeft != null || _c.sleepAtChapterEnd,
            ),
          ),
          if (showChapterButton && chapters.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _showChapters,
              child: const _PlayerAction(
                icon: Icons.format_list_bulleted,
                label: 'Chapters',
              ),
            ),
          if (AudioBookmarking.repository case final store?) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _addBookmark,
              child: const _PlayerAction(
                icon: Icons.bookmark_add_outlined,
                label: 'Bookmark',
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _showBookmarks,
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) {
                  final count = _c.bookId == null
                      ? 0
                      : store.bookmarksFor(_c.bookId!).length;
                  return _PlayerAction(
                    icon: Icons.bookmarks_outlined,
                    label: count == 0 ? 'Bookmarks' : 'Bookmarks ($count)',
                  );
                },
              ),
            ),
          ],
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final book = _c.book;
        if (!_c.active || book == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Nothing is playing.')),
          );
        }
        final chapters = _c.chapters;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Listening'),
            actions: [
              IconButton(
                tooltip: 'Mini player (stays on top)',
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
                onPressed: MiniPlayer.instance.enter,
              ),
              IconButton(
                tooltip: 'Stop and close the player',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await _c.close();
                  navigator.maybePop();
                },
              ),
            ],
          ),
          extendBodyBehindAppBar: true,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primaryContainer, scheme.surface],
                stops: const [0, 0.6],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 900 && chapters.isNotEmpty;
                  final player = Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          Center(
                            child: _cover(
                              book,
                              _coverWidth(constraints, wide: wide),
                            ),
                          ),
                          const SizedBox(height: 28),
                          ..._controls(
                            context,
                            book,
                            showChapterButton: !wide,
                          ),
                        ],
                      ),
                    ),
                  );
                  if (!wide) return player;
                  return Row(
                    children: [
                      Expanded(child: player),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 340,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                'Chapters',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Expanded(
                              child: _ChapterList(
                                chapters: [for (final c in chapters) c.title],
                                current: _c.chapterIndex,
                                onTap: _c.goToChapter,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// As big as fits: most of the width on a phone, and leaving room for the
  /// buttons below it.
  double _coverWidth(BoxConstraints constraints, {required bool wide}) {
    final byWidth = wide ? 420.0 : constraints.maxWidth - 96;
    final byHeight = constraints.maxHeight * 0.42 / 1.5;
    var width = byWidth < byHeight ? byWidth : byHeight;
    if (width > 300) width = 300;
    if (width < 120) width = 120;
    return width;
  }
}

/// Speed, sleep timer or chapters: an icon with a word under it.
class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = active ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colour),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colour,
                ),
          ),
        ],
      ),
    );
  }
}

/// The book's chapters, with the one playing marked.
class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.chapters,
    required this.current,
    required this.onTap,
    this.controller,
  });

  final List<String> chapters;
  final int? current;
  final void Function(int index) onTap;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: controller,
      itemCount: chapters.length,
      itemBuilder: (context, i) {
        final playing = i == current;
        return ListTile(
          selected: playing,
          selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.5),
          leading: SizedBox(
            width: 28,
            child: playing
                ? Icon(Icons.graphic_eq, color: scheme.primary)
                : Text(
                    '${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
          ),
          title: Text(chapters[i]),
          onTap: () => onTap(i),
        );
      },
    );
  }
}
