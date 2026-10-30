import 'dart:async';

import 'package:flutter/material.dart';

import '../data/window_control.dart';

/// "01:02:03" for one hour, two minutes and three seconds.
String formatClock(Duration elapsed) {
  final total = elapsed.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(hours)}:${two(minutes)}:${two(seconds)}';
}

/// The reading timer's stopwatch, shared by the timer dialog and the small
/// window, so the time keeps going when you switch between them.
class ReadingStopwatch extends ChangeNotifier {
  final _watch = Stopwatch();
  Timer? _ticker;

  Duration get elapsed => _watch.elapsed;
  bool get isRunning => _watch.isRunning;
  bool get started => _watch.elapsed.inSeconds > 0;
  String get clock => formatClock(_watch.elapsed);

  void toggle() {
    if (_watch.isRunning) {
      _watch.stop();
      _ticker?.cancel();
      _ticker = null;
    } else {
      _watch.start();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Shrinks Chapterly to a small window that stays on top of other windows
/// and shows only the reading timer, and puts it back afterwards.
class MiniTimer extends ChangeNotifier {
  MiniTimer({WindowControl? window}) : window = window ?? NoWindowControl();

  /// The one the app uses. main.dart gives it the real window.
  static final instance = MiniTimer();

  /// The size of the small window.
  static const size = Size(320, 170);

  WindowControl window;
  ReadingStopwatch? _watch;
  Rect? _saved;
  bool _wasMaximized = false;
  bool _switching = false;

  /// Whether the small window is showing.
  bool get active => _watch != null;

  /// The stopwatch shown in the small window.
  ReadingStopwatch? get stopwatch => _watch;

  Future<void> enter(ReadingStopwatch watch) async {
    if (active || _switching) return;
    _switching = true;
    try {
      _wasMaximized = await window.isMaximized();
      if (_wasMaximized) await window.unmaximize();
      final bounds = await window.getBounds();
      _saved = bounds;
      _watch = watch;
      notifyListeners();
      await window.setMinimumSize(const Size(240, 120));
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
    if (!active || _switching) return;
    _switching = true;
    try {
      await window.setAlwaysOnTop(false);
      final saved = _saved;
      if (saved != null) await window.setBounds(saved);
      await window.setMinimumSize(normalMinimumSize);
      if (_wasMaximized) await window.maximize();
      _watch = null;
      notifyListeners();
    } finally {
      _switching = false;
    }
  }
}

/// Wraps the whole app. While the small timer window is showing, the app is
/// kept as it was (at its old size, out of sight) and only the timer shows.
class MiniTimerHost extends StatefulWidget {
  const MiniTimerHost({super.key, required this.child, this.controller});

  final Widget child;
  final MiniTimer? controller;

  @override
  State<MiniTimerHost> createState() => _MiniTimerHostState();
}

class _MiniTimerHostState extends State<MiniTimerHost> {
  Size? _normalSize;

  MiniTimer get _controller => widget.controller ?? MiniTimer.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final watch = _controller.stopwatch;
        return LayoutBuilder(
          builder: (context, constraints) {
            final mini = watch != null;
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
                if (watch != null)
                  Positioned.fill(
                    child: _MiniTimerView(
                      watch: watch,
                      onBack: _controller.leave,
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

class _MiniTimerView extends StatelessWidget {
  const _MiniTimerView({required this.watch, required this.onBack});

  final ReadingStopwatch watch;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      child: ListenableBuilder(
        listenable: watch,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(watch.clock, style: textTheme.headlineMedium),
                ),
              ),
              // No tooltips here: this view sits above the app's overlay.
              IconButton(
                icon: Icon(
                  watch.isRunning ? Icons.pause : Icons.play_arrow,
                  semanticLabel: watch.isRunning ? 'Pause' : 'Start',
                ),
                onPressed: watch.toggle,
              ),
              IconButton(
                icon: const Icon(
                  Icons.open_in_full,
                  semanticLabel: 'Back to Chapterly',
                ),
                onPressed: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
