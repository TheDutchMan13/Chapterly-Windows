import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../audio/listen_controller.dart';
import '../audio/listening.dart';
import '../screens/mini_player.dart';
import 'app_settings.dart';

// Windows app only.

/// Keeps Chapterly running in the system tray when its window is closed
/// (when that is switched on in Settings), so an audiobook keeps playing.
/// Click the tray icon to bring the window back; right-click it for Play,
/// the mini player, and Quit.
class AppTray with tray.TrayListener, WindowListener {
  AppTray(this.settings);

  final AppSettings settings;

  bool _inTray = false;
  bool _applying = false;
  bool? _menuPlaying;
  bool? _menuActive;

  ListenController? get _player => Listening.controller;

  Future<void> start() async {
    windowManager.addListener(this);
    tray.trayManager.addListener(this);
    settings.addListener(_settingsChanged);
    _player?.addListener(_playerChanged);
    await _apply();
  }

  void _settingsChanged() => unawaited(_apply());

  Future<void> _apply() async {
    if (_applying) return;
    _applying = true;
    try {
      while (settings.closeToTray != _inTray) {
        final want = settings.closeToTray;
        if (want) {
          await windowManager.setPreventClose(true);
          await tray.trayManager.setIcon('assets/tray_icon.ico');
          await tray.trayManager.setToolTip('Chapterly');
          _inTray = true;
          await _setMenu();
        } else {
          await windowManager.setPreventClose(false);
          await tray.trayManager.destroy();
          _inTray = false;
        }
      }
    } catch (_) {
      // No tray on this PC: closing the window closes Chapterly as before.
    } finally {
      _applying = false;
    }
  }

  void _playerChanged() {
    final player = _player;
    if (!_inTray || player == null) return;
    if (player.playing == _menuPlaying && player.active == _menuActive) return;
    unawaited(_setMenu());
  }

  Future<void> _setMenu() async {
    final player = _player;
    final active = player?.active ?? false;
    final playing = player?.playing ?? false;
    _menuActive = active;
    _menuPlaying = playing;
    await tray.trayManager.setContextMenu(tray.Menu(items: [
      tray.MenuItem(key: 'show', label: 'Show Chapterly'),
      if (active) ...[
        tray.MenuItem(key: 'play', label: playing ? 'Pause' : 'Play'),
        tray.MenuItem(key: 'mini', label: 'Mini player'),
      ],
      tray.MenuItem.separator(),
      tray.MenuItem(key: 'quit', label: 'Quit Chapterly'),
    ]));
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Closes Chapterly for real, saving where you are in the audiobook.
  Future<void> quit() async {
    final player = _player;
    if (player != null && player.playing) {
      await player.pause();
      // Give the place a moment to be saved.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await tray.trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowClose() {
    // Without the tray, Windows closes Chapterly as usual.
    if (!_inTray) return;
    if (settings.closeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(quit());
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(_show());

  @override
  void onTrayIconRightMouseDown() => unawaited(tray.trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_show());
      case 'play':
        final player = _player;
        if (player != null) unawaited(player.toggle());
      case 'mini':
        unawaited(() async {
          await _show();
          await MiniPlayer.instance.enter();
        }());
      case 'quit':
        unawaited(quit());
    }
  }
}
