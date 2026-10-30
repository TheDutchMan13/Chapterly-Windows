import 'package:flutter/material.dart';

import '../audio/listen_controller.dart';
import '../audio/listening.dart';
import '../data/book_repository.dart';
import '../models/audio_progress.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'listen_card.dart';

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
    final chapters = _c.chapters;
    final current = _c.chapterIndex;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: chapters.length,
          itemBuilder: (context, i) => ListTile(
            selected: i == current,
            leading: Text('${i + 1}'),
            title: Text(chapters[i].title),
            onTap: () => Navigator.of(sheetContext).pop(i),
          ),
        ),
      ),
    );
    if (chosen != null) await _c.goToChapter(chosen);
  }

  String _sleepLabel() {
    if (_c.sleepAtChapterEnd) return 'End of chapter';
    final left = _c.sleepLeft;
    if (left == null) return 'Sleep timer';
    return '${formatPlayerClock(left)} left';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Listening'),
            actions: [
              if (chapters.isNotEmpty)
                IconButton(
                  tooltip: 'Chapters',
                  icon: const Icon(Icons.list),
                  onPressed: _showChapters,
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
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: BookCover(
                      coverUrl: book.coverUrl,
                      width: 180,
                      height: 270,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    book.title,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge,
                  ),
                  if (book.author.isNotEmpty)
                    Text(
                      book.author,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  if (index != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Chapter ${index + 1} of ${chapters.length}: '
                      '${chapters[index].title}',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Slider(
                    value: total <= 0 ? 0 : slider,
                    max: total <= 0 ? 1 : total,
                    onChanged: total <= 0
                        ? null
                        : (value) => setState(() => _dragging = value),
                    onChangeEnd: total <= 0
                        ? null
                        : (value) {
                            setState(() => _dragging = null);
                            _c.seekInTrack(
                              start + Duration(milliseconds: value.round()),
                            );
                          },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Text(formatPlayerClock(
                          Duration(milliseconds: slider.round()),
                        )),
                        const Spacer(),
                        Text(
                          '-${formatPlayerClock(
                            Duration(milliseconds: (total - slider).round()),
                          )}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      describeAudioProgress(progress, _c.link),
                      if (leftMs != null && leftMs > 0)
                        '${formatListenTime(leftMs ~/ _c.speed)} left'
                            '${_c.speed == 1 ? '' : ' at ${_speedLabel(_c.speed)}'}',
                    ].join(' · '),
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Previous chapter',
                        iconSize: 32,
                        icon: const Icon(Icons.skip_previous),
                        onPressed:
                            chapters.isEmpty ? null : _c.previousChapter,
                      ),
                      IconButton(
                        tooltip: 'Back 30 seconds',
                        iconSize: 32,
                        icon: const Icon(Icons.replay_30),
                        onPressed: () =>
                            _c.skip(const Duration(seconds: -30)),
                      ),
                      IconButton.filled(
                        tooltip: _c.playing ? 'Pause' : 'Play',
                        iconSize: 48,
                        icon: Icon(_c.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: _c.toggle,
                      ),
                      IconButton(
                        tooltip: 'Forward 30 seconds',
                        iconSize: 32,
                        icon: const Icon(Icons.forward_30),
                        onPressed: () => _c.skip(const Duration(seconds: 30)),
                      ),
                      IconButton(
                        tooltip: 'Next chapter',
                        iconSize: 32,
                        icon: const Icon(Icons.skip_next),
                        onPressed: chapters.isEmpty ? null : _c.nextChapter,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
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
                        child: Chip(
                          avatar: const Icon(Icons.speed, size: 18),
                          label: Text(_speedLabel(_c.speed)),
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
                            PopupMenuItem(
                              value: minutes,
                              child: Text('$minutes minutes'),
                            ),
                          if (chapters.isNotEmpty)
                            const PopupMenuItem(
                              value: -1,
                              child: Text('End of this chapter'),
                            ),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.bedtime_outlined, size: 18),
                          label: Text(_sleepLabel()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
