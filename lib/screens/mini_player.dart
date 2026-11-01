import 'package:flutter/material.dart';

import '../audio/listen_controller.dart';
import '../audio/listening.dart';
import '../data/window_control.dart';
import '../widgets/book_cover.dart';
import 'mini_timer.dart';

// Windows app only.

/// Shrinks Chapterly to a small window that stays on top of other windows
/// and shows only the audiobook playing, and puts it back afterwards.
class MiniPlayer extends ChangeNotifier {
  MiniPlayer({WindowControl? window}) : window = window ?? NoWindowControl();

  /// The one the app uses. main.dart gives it the real window.
  static final instance = MiniPlayer();

  /// The size of the small window.
  static const size = Size(400, 128);

  WindowControl window;
  Rect? _saved;
  bool _wasMaximized = false;
  bool _switching = false;
  bool _active = false;

  /// Whether the small window is showing.
  bool get active => _active;

  Future<void> enter() async {
    if (_active || _switching || MiniTimer.instance.active) return;
    _switching = true;
    try {
      _wasMaximized = await window.isMaximized();
      if (_wasMaximized) await window.unmaximize();
      final bounds = await window.getBounds();
      _saved = bounds;
      _active = true;
      notifyListeners();
      await window.setMinimumSize(const Size(300, 110));
      await window.setBounds(
        Rect.fromLTWH(
          bounds.right - size.width - 24,
          bounds.top + 24,
          size.width,
          size.height,
        ),
      );
      await window.setAlwaysOnTop(true);
    } finally {
      _switching = false;
    }
  }

  Future<void> leave() async {
    if (!_active || _switching) return;
    _switching = true;
    try {
      await window.setAlwaysOnTop(false);
      final saved = _saved;
      if (saved != null) await window.setBounds(saved);
      await window.setMinimumSize(normalMinimumSize);
      if (_wasMaximized) await window.maximize();
      _active = false;
      notifyListeners();
    } finally {
      _switching = false;
    }
  }
}

/// Wraps the whole app. While the mini player is showing, the app is kept as
/// it was (at its old size, out of sight) and only the player shows.
class MiniPlayerHost extends StatefulWidget {
  const MiniPlayerHost({super.key, required this.child, this.controller});

  final Widget child;
  final MiniPlayer? controller;

  @override
  State<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<MiniPlayerHost> {
  Size? _normalSize;

  MiniPlayer get _mini => widget.controller ?? MiniPlayer.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _mini,
      builder: (context, _) {
        final player = Listening.controller;
        final mini = _mini.active && player != null;
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!mini) _normalSize = constraints.biggest;
            final size = _normalSize ?? constraints.biggest;
            return Stack(
              children: [
                Offstage(
                  offstage: mini,
                  child: TickerMode(
                    enabled: !mini,
                    child: ExcludeFocus(
                      excluding: mini,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          minHeight: 0,
                          maxWidth: mini ? size.width : constraints.maxWidth,
                          maxHeight: mini ? size.height : constraints.maxHeight,
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
                if (mini)
                  Positioned.fill(
                    child: _MiniPlayerView(
                      controller: player,
                      onBack: _mini.leave,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerView extends StatelessWidget {
  const _MiniPlayerView({required this.controller, required this.onBack});

  final ListenController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final book = controller.book;
          if (!controller.active || book == null) {
            // Nothing playing any more: go back to the full window.
            WidgetsBinding.instance.addPostFrameCallback((_) => onBack());
            return const SizedBox.shrink();
          }
          final chapters = controller.chapters;
          final index = controller.chapterIndex;
          final fraction = controller.progress?.fraction;
          return Column(
            children: [
              LinearProgressIndicator(value: fraction ?? 0, minHeight: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(
                    children: [
                      BookCover(coverUrl: book.coverUrl, width: 52, height: 76),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall,
                            ),
                            if (index != null && index < chapters.length)
                              Text(
                                chapters[index].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall,
                              ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Back 30 seconds',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.replay_30),
                                  onPressed: () => controller
                                      .skip(const Duration(seconds: -30)),
                                ),
                                IconButton(
                                  tooltip:
                                      controller.playing ? 'Pause' : 'Play',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    controller.playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                                  onPressed: controller.toggle,
                                ),
                                IconButton(
                                  tooltip: 'Forward 30 seconds',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.forward_30),
                                  onPressed: () => controller
                                      .skip(const Duration(seconds: 30)),
                                ),
                                IconButton(
                                  tooltip: 'Next chapter',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.skip_next),
                                  onPressed: chapters.isEmpty
                                      ? null
                                      : controller.nextChapter,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Back to Chapterly',
                        icon: const Icon(Icons.open_in_full),
                        onPressed: onBack,
                      ),
                    ],
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
