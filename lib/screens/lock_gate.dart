import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../data/pin_lock.dart';
import '../data/profiles.dart';
import 'profiles_screen.dart';

/// Hides the app behind a PIN screen when a PIN is set: when the app starts,
/// and when it comes back after being away longer than the chosen time.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.settings, required this.child});

  final AppSettings settings;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked = widget.settings.pinEnabled;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_settingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_settingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _settingsChanged() {
    if (_locked && !widget.settings.pinEnabled) {
      setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Minimized on Windows is "hidden", not "paused": either one starts
    // the time away.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          widget.settings.pinEnabled &&
          DateTime.now().difference(left).inSeconds >=
              widget.settings.lockAfterSeconds) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Kept alive behind the lock, but it takes no keys (such as Ctrl+V
        // for a cover) while locked.
        ExcludeFocus(
          excluding: _locked,
          child: Visibility(
            visible: !_locked,
            maintainState: true,
            child: widget.child,
          ),
        ),
        if (_locked)
          Positioned.fill(
            child: _PinScreen(
              settings: widget.settings,
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}

/// The PIN screen. It uses its own number pad instead of a text field,
/// because it sits above the app's navigator where text fields cannot show
/// their selection handles.
class _PinScreen extends StatefulWidget {
  const _PinScreen({required this.settings, required this.onUnlocked});

  final AppSettings settings;
  final VoidCallback onUnlocked;

  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  static const _maxLength = 8;

  Timer? _timer;
  String _entry = '';
  int _waiting = 0;
  String? _error;
  bool _choosingProfile = false;
  bool _checking = false;

  /// Wrong PINs are counted in the settings, so a restart does not give
  /// more tries.
  final Future<PinGuard> _guard = PinGuard.load();

  @override
  void initState() {
    super.initState();
    _guard.then((guard) {
      if (mounted) _startWait(guard.waitLeft);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startWait(Duration wait) {
    _timer?.cancel();
    if (wait <= Duration.zero) return;
    setState(() {
      _entry = '';
      _error = null;
      _waiting = (wait.inMilliseconds / 1000).ceil();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _waiting--);
      if (_waiting <= 0) timer.cancel();
    });
  }

  /// Typing on the keyboard works as well as the number pad.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _erase();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_check());
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null && RegExp(r'^[0-9]$').hasMatch(character)) {
      _type(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _type(String digit) {
    if (_waiting > 0 || _entry.length >= _maxLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
  }

  void _erase() {
    if (_waiting > 0 || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _check() async {
    if (_waiting > 0 || _entry.isEmpty || _checking) return;
    _checking = true;
    try {
      final guard = await _guard;
      if (!mounted) return;
      final left = guard.waitLeft;
      if (left > Duration.zero) {
        _startWait(left);
        return;
      }
      final right = await widget.settings.checkPinAsync(_entry);
      if (!mounted) return;
      if (right) {
        await guard.recordSuccess();
        widget.onUnlocked();
        return;
      }
      final wait = await guard.recordFailure();
      if (!mounted) return;
      if (wait > Duration.zero) {
        _startWait(wait);
      } else {
        setState(() {
          _entry = '';
          _error = 'Wrong PIN.';
        });
      }
    } finally {
      _checking = false;
    }
  }

  Widget _digit(String digit) => SizedBox(
        width: 72,
        height: 64,
        child: TextButton(
          onPressed: _waiting > 0 ? null : () => _type(digit),
          child: Text(digit, style: Theme.of(context).textTheme.headlineSmall),
        ),
      );

  Widget _row(List<Widget> keys) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys,
      );

  @override
  Widget build(BuildContext context) {
    final message = _waiting > 0
        ? pinWaitMessage(Duration(seconds: _waiting))
        : _error;
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Chapterly is locked',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (ProfileSwitching.store case final profiles?
                      when profiles.hasOthers) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProfileAvatar(profile: profiles.active, radius: 12),
                        const SizedBox(width: 8),
                        Text(profiles.active.name),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    child: Text(
                      '\u2022 ' * _entry.length,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: Text(
                      message ?? '',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _row([_digit('1'), _digit('2'), _digit('3')]),
                  _row([_digit('4'), _digit('5'), _digit('6')]),
                  _row([_digit('7'), _digit('8'), _digit('9')]),
                  _row([
                    SizedBox(
                      width: 72,
                      height: 64,
                      child: IconButton(
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: _waiting > 0 ? null : _erase,
                      ),
                    ),
                    _digit('0'),
                    SizedBox(
                      width: 72,
                      height: 64,
                      child: IconButton.filled(
                        icon: const Icon(Icons.check),
                        onPressed: _waiting > 0 ? null : _check,
                      ),
                    ),
                  ]),
                  if (ProfileSwitching.store case final profiles?
                      when profiles.hasOthers) ...[
                    const SizedBox(height: 16),
                    if (!_choosingProfile)
                      TextButton.icon(
                        icon: const Icon(Icons.people_outline),
                        label: const Text('Open another profile'),
                        onPressed: () =>
                            setState(() => _choosingProfile = true),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final profile in profiles.profiles)
                            if (profile.id != profiles.active.id)
                              ActionChip(
                                avatar: ProfileAvatar(
                                  profile: profile,
                                  radius: 12,
                                ),
                                label: Text(profile.name),
                                onPressed: () =>
                                    ProfileSwitching.switchTo?.call(profile.id),
                              ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
