import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// The smallest the main window may be, so the library never gets squashed.
const normalMinimumSize = Size(480, 640);

/// The few things Chapterly does to its own window. The app uses
/// [PluginWindowControl]; tests use [NoWindowControl].
abstract interface class WindowControl {
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<void> setAlwaysOnTop(bool onTop);
  Future<void> setMinimumSize(Size size);
}

/// Uses the window_manager plugin.
class PluginWindowControl implements WindowControl {
  const PluginWindowControl();

  /// Call once before the app starts.
  static Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(normalMinimumSize);
  }

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<void> setAlwaysOnTop(bool onTop) =>
      windowManager.setAlwaysOnTop(onTop);

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);
}

/// Does nothing, and remembers what it was asked. For tests.
class NoWindowControl implements WindowControl {
  Rect bounds = const Rect.fromLTWH(100, 100, 1200, 800);
  bool maximized = false;
  bool onTop = false;
  Size minimumSize = normalMinimumSize;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<void> setBounds(Rect value) async {
    bounds = value;
  }

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> maximize() async {
    maximized = true;
  }

  @override
  Future<void> unmaximize() async {
    maximized = false;
  }

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    onTop = value;
  }

  @override
  Future<void> setMinimumSize(Size size) async {
    minimumSize = size;
  }
}
